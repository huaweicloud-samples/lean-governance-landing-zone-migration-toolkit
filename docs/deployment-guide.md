# 部署指导书

> 本文按可复现的步骤说明如何部署并验证多账号着陆区治理基线。
> 每步都给出命令与预期输出，便于逐项核对。

## 一、部署总览

部署分三段：

| 段 | 内容 | 涉及目录 |
|---|---|---|
| 基础部署 | 在管理账号建立日志底座、基线网络、运营委托、护栏、告警 | `infra/` |
| 多账号下发 | 建立资源栈集并向目标账号下发基线 | `infra/`（模板在 `infra/stackset/`） |
| 既有资源接管 | 把已有基线资源纳入状态管理 | `infra/takeover/`（独立工作区） |
| 链路操作 | 盘点 → 接管 → 交接 → 退役 | `scripts/` |

先完成基础部署，再按需做多账号下发；接管与链路操作在多账号下发之后进行。

> **目录结构说明**：`infra/takeover/` 是一个**独立的 Terraform 工作区**，与 `infra/` 主装配互不引用。原因是声明式接管（import 块）要求 import 的目标是不带索引的资源，而主装配中的资源普遍带 `count`；带索引的资源无法被 import 块引用，只能改用命令式接管。因此接管链路单独成区。

## 二、前置准备

### 2.1 获取访问凭据

在华为云「我的凭证」页面获取 Access Key ID 与 Secret Access Key。

```bash
export HW_ACCESS_KEY="<your-access-key>"
export HW_SECRET_KEY="<your-secret-key>"
```

使用临时凭据时追加：

```bash
export HW_SECURITY_TOKEN="<your-security-token>"
```

> 凭据只通过环境变量传入，不写入任何脚本或配置文件。

### 2.2 确认组织关系

区域访问护栏依赖组织结构。部署前确认：

- 已建立组织，且账号具备组织策略管理权限
- 已知组织根节点 ID，或目标组织单元 ID
- 已知可代入基线委托的管理账号 domain name

三项标识从控制台「组织」与「IAM」页面获取。

### 2.3 确认栈集下发权限

栈集下发要求管理委托具备 `iam:tokens:assume` 权限。该权限是域级的，普通 IAM 子账号无法自行挂载，需由具备 Security Administrator 的账号授予。

若该权限未授予，栈集创建与实例创建都会返回权限错误。

### 2.4 准备栈集模板

栈集模板是 Terraform HCL 文件，本仓库提供在 `infra/stackset/baseline-template.tf`。

模板有两种提交方式，**二选一**：

| 方式 | 配置项 | 说明 |
|---|---|---|
| 内联提交（推荐） | `stack_set_template_file = "stackset/baseline-template.tf"` | 模板内容随栈集一并提交，不依赖外部存储，无需额外准备可读地址 |
| 地址拉取 | `stack_set_template_url = "<模板地址>"` | 从指定地址拉取模板，地址须能被资源编排服务读取 |

> 优先用内联方式。地址方式要求模板所在的存储桶对编排服务可读，而私有桶默认返回 `403 AccessDenied`；实测中桶策略与匿名读两种方式均无法解决该问题，改用内联模板后完全绕开此约束。

模板要求：

- 必须是 Terraform HCL，且**不得**声明 provider 配置块 —— 资源编排服务在部署时自动注入 provider 配置，手写占位符会导致部署失败
- provider 来源必须是资源编排服务可检索的**内部地址** `huawei.com/provider/huaweicloud`，并锁定版本；用公共地址会导致服务端无法检索版本列表，栈直接进入部署失败
- 块语法须遵循 HCL2：块体内的属性与子块需换行书写，单行块写法会被判为模板格式非法
- 变量以 tfvars 格式传入，即每行 `key = "value"`

## 三、基础部署

### 3.1 初始化

```bash
cd lean-governance-landing-zone-migration-toolkit/infra
terraform init
```

**预期输出**：`Terraform has been successfully initialized!`

### 3.2 准备变量文件

```bash
cat > terraform.tfvars <<'EOF'
region                      = "cn-north-4"
project_name                = "landing-zone-governance"
vpc_cidr                    = "10.0.0.0/16"
subnet_cidr                 = "10.0.1.0/24"
approved_regions            = ["cn-north-4", "cn-east-3"]
organization_root_id        = "<your-organization-root-id>"
agency_trusted_account_id   = "<your-management-account-domain-name>"
notification_recipients     = ["ops-team@example.com"]
EOF
```

按实际填写各项标识。`organization_root_id` 与 `agency_trusted_account_id` 留空时，对应的资源会被跳过创建。

### 3.3 预演

```bash
terraform plan
```

**预期输出**：`Plan: N to add, 0 to change, 0 to destroy.`

逐项核对 plan 内容，确认将要创建的资源与预期一致。

### 3.4 执行

```bash
terraform apply -auto-approve
```

**预期输出**：`Apply complete! Resources: N added, 0 changed, 0 destroyed.`

### 3.5 记录输出

```bash
terraform output
```

**预期输出**：列出基线 VPC ID、子网 ID、流日志 ID、护栏策略 ID、告警主题 URN 等。

把 `log_group_id` 与 `log_stream_id` 记下来，后续验证脚本要用。

## 四、多账号下发

### 4.1 启用栈集

在 `terraform.tfvars` 中追加：

```hcl
enable_stack_set            = true
stack_set_target_account_ids = ["<account-id-1>", "<account-id-2>"]
stack_set_target_regions    = ["cn-north-4"]

# 模板来源（二选一）
stack_set_template_file      = "stackset/baseline-template.tf"
# stack_set_template_url     = "<your-obs-internal-template-url>"

# 权限模型：自管模式需同时提供管理委托与被管理委托
stack_set_permission_model            = "SELF_MANAGED"
stack_set_administration_agency_name = "<management-agency-name>"
stack_set_managed_agency_name        = "<managed-agency-name>"

stack_set_vars = {
  vpc_cidr    = "10.0.0.0/16"
  subnet_cidr = "10.0.1.0/24"
}
```

> **模板变更须知**：栈集模板提交后，服务端**不支持对既有栈集原地更新模板**，此时 `terraform plan` 会直接报 `template_body can't be updated`。若确需变更模板，把 `stack_set_enable_force_new` 置为 `"true"`，变更会转为「销毁旧栈集与部署 + 重建」。注意替换会中断该栈集上已存在的下发实例，变更前应确认目标账号侧无需保留当前实例。

> **权限模型注意**：自管模式下**不要**传 `call_identity`——它只在服务托管模式（`SERVICE_MANAGED`）下有意义，自管模式下传入会被判为多余参数而报错。产物已按权限模型自动条件传参。

### 4.2 执行下发

```bash
terraform apply -auto-approve
```

**预期输出**：除常规资源外，栈集实例创建步骤会输出操作轮询日志，最终显示 `栈集实例创建完成`。

### 4.3 确认实例真实存在

```bash
python3 ../scripts/rfs_stack_instance.py list --stack-set landing-zone-governance-baseline
```

**预期输出**：
```
  账号=<account-id-1> 区域=cn-north-4 状态=CREATE_COMPLETE
共 1 个栈集实例
```

> **这一步不可省略**。栈集定义与栈集部署成功不代表实例已创建 —— 实例创建是独立动作。没有这一步的确认，就无法判断下发链路是否真的走通。

## 五、链路操作

### 5.1 盘点

```bash
cd ..
python3 scripts/extract-manifest.py scripts/baseline-manifest.yaml json
```

**预期输出**：包含 `total_accounts`、`total_customizations` 与逐条明细的 JSON。

### 5.2 接管既有资源

接管在**独立工作区** `infra/takeover/` 中进行（原因见 §一 目录结构说明）。

**步骤一**：初始化接管工作区。

```bash
cd infra/takeover
terraform init
```

**步骤二**：填写待接管资源的真实属性。

编辑 `infra/takeover/variables.tf` 中的 `takeover_targets`，逐项填入线上实际属性：

```hcl
takeover_targets = {
  vpc = {
    name        = "landing-zone-governance-vpc"
    cidr        = "10.0.0.0/16"
    description = "Account baseline VPC managed by the landing zone governance"
    tags = {
      ManagedBy = "landing-zone-governance"
      Name      = "landing-zone-governance-vpc"
    }
  }
  subnet = {
    name       = "landing-zone-governance-subnet"
    cidr       = "10.0.1.0/24"
    gateway_ip = "10.0.1.1"
    tags = { ManagedBy = "landing-zone-governance", Name = "landing-zone-governance-subnet" }
  }
  flow_log = {
    name          = "landing-zone-governance-flowlog"
    description   = "Baseline VPC flow log for the landing zone governance"
    log_group_id  = "<lts-group-id>"
    log_stream_id = "<lts-stream-id>"
  }
  secgroup = {
    name        = "landing-zone-governance-default-sg-tightened"
    description = "Tightened default security group for the baseline VPC"
    tags = { ManagedBy = "landing-zone-governance", Name = "landing-zone-governance-default-sg-tightened" }
  }
  agency = {
    name                = "landing-zone-governance-ops-agency"
    description         = "Baseline operations agency for the landing zone governance"
    trusted_domain_name = "<trusted-domain-name>"
    roles               = []
  }
}
```

> **标签必须与线上一致**：线上资源通常带有服务自动生成的 `Name` 标签，漏填或多填都会在接管后产生漂移变更。
>
> **安全组不要填 `delete_default_rules`**：该参数是创建期专属字段，读回时恒为空，声明它会触发「销毁 + 重建」——这正是接管要避免的副作用。

各资源类型的接管标识格式：

| 资源 | 标识格式 |
|---|---|
| VPC | `<vpc_id>` |
| 子网 | `<subnet_id>` |
| VPC 流日志 | `<flow_log_id>`（**不带** VPC ID 前缀） |
| 安全组 | `<secgroup_id>` |
| 委托 | `<agency_id>`（**不是**委托名称） |
| 资源栈 | `<stack_name>` |
| LTS 日志组 | `<group_id>` |
| LTS 日志流 | `<group_id>/<stream_id>` |

**步骤三**：取消 import 块的注释。

编辑 `infra/takeover/import-blocks.tf`，把对应 import 块的注释去掉并填入真实标识。

**步骤四**：跑零漂移校验。

```bash
./scripts/verify-takeover.sh infra/takeover
```

**预期输出**：
```
待接管 (to import): 5
待新增 (to add):    0
待变更 (to change): 0
待删除 (to destroy): 0
需重建 (replace):   0

✓ 校验通过：5 个对象待接管，其余无任何变更
```

**步骤五**：校验通过后执行接管。

```bash
cd infra/takeover && terraform apply -auto-approve
```

**步骤六**：接管成功后**删除 import 块** —— 它是临时的接管声明，不是长期配置。

### 5.3 交接

```bash
cd ..
./scripts/remove-stack-instances.sh \
  --stack-set landing-zone-governance-baseline \
  --account-id <account-id-1> \
  --regions cn-north-4
```

脚本会先要求确认该账号资源已完成接管，然后移除实例，并打印后续校验命令。

立即执行校验，确认底层资源未被连带删除：

```bash
python3 scripts/verify-account-resources.py \
  --region cn-north-4 \
  --expect-vpc 10.0.0.0/16 \
  --expect-subnet 10.0.1.0/24 \
  --expect-flow-log \
  --expect-agency landing-zone-governance-ops-agency
```

**预期输出**：全部校验项通过，失败 0 项。

### 5.4 退役

按步骤依次执行，每步之间留观察期：

```bash
# 第 1 步：停用自动化下发
./scripts/decommission.sh --stack-set landing-zone-governance-baseline --step 1

# 观察期 2-4 周，确认无治理异常告警

# 第 2 步：移除空栈集实例
./scripts/decommission.sh --stack-set landing-zone-governance-baseline --step 2

# 第 3 步：删除栈集定义
./scripts/decommission.sh --stack-set landing-zone-governance-baseline --step 3

# 第 4 步：删除残留资源栈
./scripts/decommission.sh --stack-set landing-zone-governance-baseline --step 4

# 第 5 步：归档留痕（不可逆）
./scripts/decommission.sh --stack-set landing-zone-governance-baseline --step 5
```

第 5 步前需确认四项前提：第 1-4 步已全部完成、观察期内无异常告警、所有账号资源对等校验通过、全部账号的治理标签已更新。

## 六、验证清单

部署完成后逐项核对：

| # | 验证项 | 命令 | 通过标准 |
|---|---|---|---|
| 1 | 基线资源存在 | `verify-account-resources.py` | 全部项通过，失败 0 项 |
| 2 | 接管零漂移 | `verify-takeover.sh infra/takeover` | 仅有 import 条目，无增删改 |
| 3 | 清单盘点 | `extract-manifest.py` | 覆盖全部账号与定制项 |
| 4 | 栈集实例存在 | `rfs_stack_instance.py list` | 实例状态为 `OPERATION_COMPLETE` |
| 5 | 护栏生效 | 控制台切换到白名单外地域发起查询 | 调用被拒绝 |
| 6 | 交接后资源保留 | 移除实例后重跑验证 1 | 仍然全部通过 |
| 7 | 格式与语法 | `terraform fmt -check -recursive` + `terraform validate` | 无输出 / `Success!` |

## 七、常见问题定位

| 现象 | 排查方向 |
|---|---|
| apply 报权限不足 | 确认 Tenant Administrator 权限；栈集场景另需 `iam:tokens:assume` |
| 栈集创建成功但目标账号无资源 | 查 `rfs_stack_instance.py list`；实例创建是独立动作，需确认该步骤已执行 |
| plan 报 `template_body can't be updated` | 栈集模板不支持原地更新；把 `stack_set_enable_force_new` 置 `"true"` 转为替换重建 |
| 栈下发报 `Could not retrieve the list of available versions for provider` | 模板内 provider 源须改为 `huawei.com/provider/huaweicloud` 并锁版本，公共地址服务端检索不到 |
| 栈下发报 `RF.10011168 Invalid template content` | 模板用了 HCL1 单行块语法；块体内属性与子块须换行书写 |
| 栈集创建报 `RF.10031098 Extra parameter(s): [call_identity]` | 自管模式下不要传 `call_identity`，它只在服务托管模式（`SERVICE_MANAGED`）下有意义 |
| 栈集创建报 `RF.10031082 VirtualHostDomainRequired` | 模板地址须为 VirtualHost 域名形式（`https://<桶>.obs.<区域>.myhuaweicloud.com/<键>`），路径形式不被接受 |
| 栈集创建报 `RF.10031028 [permission_model] [MANAGED] is not a valid enum value` | 权限模型合法值只有 `SELF_MANAGED` 与 `SERVICE_MANAGED`，没有 `MANAGED` |
| 栈集创建报 `RF.10032569 Your account is not a member of an organization` | 选用了 `SERVICE_MANAGED`，该模式要求当前账号属于某个组织；独立账号请用 `SELF_MANAGED` |
| 栈实例下发报 `AssumeFrom domain is not trusted` | 管理委托必须是**服务型委托**（`delegated_service_name = "op_svc_iac"`），账号型委托无法被编排服务代入；改对后错误前移为被管理委托的 `iam:assume` 授权问题 |
| 栈实例下发报 `You do not have permission to perform action iam:assume on resource *` | 被管理委托缺 `iam:assume` 授权，需由**管理账号**侧授权；下发拓扑须为「管理账号 + 成员账号」双账号，单账号无法闭环 |
| 委托创建报 `Could not find domain: <domain_id>` | `delegated_domain_name` 要的是**域名称**而非域 ID（本账号域名为 `GT-dgcmy`，ID↔名称用 `GET /v3/auth/domains` 查） |
| 接管校验报漂移 | `terraform state show` 比对实际属性，重点看标签（是否缺 `Name` 键）、描述字段、启用状态、保留期 |
| 接管校验报「需重建」 | 检查是否声明了创建期专属字段（如安全组的 `delete_default_rules`），该字段声明即触发替换 |
| 每次 plan 都出现委托变更 | 委托域级角色由独立接口回读，该接口对缺少委托读取权限的身份返回 403；产物已用 `ignore_changes` 让出该字段，角色是否落地以控制台委托详情为准 |
| 护栏不拦截 | 确认策略已挂载；确认走的是组织策略路径还是托管护栏路径；核对条件键格式 |
| 告警规则创建报服务端内部错误 | 部分区域的告警规则接口不可用；`enable_monitoring` 默认关闭，开启前先在目标区域单条验证 |
| 告警不触发 | 确认 AOM 告警规则处于启用状态；确认 SMN 主题已订阅且订阅状态正常 |
| 日志无数据 | 确认流日志启用状态；确认日志组与日志流存在；确认未过保留期 |

## 八、清理

```bash
cd lean-governance-landing-zone-migration-toolkit/infra
terraform destroy -auto-approve
```

`terraform destroy` 只释放状态中追踪的资源。通过接口直接创建的资源需手工释放；账号内其他任务共享的资源不受影响。
