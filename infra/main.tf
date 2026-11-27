# ============================================================================
# 全局基线装配
# ============================================================================
# 把三块基线（日志底座 / 网络基线 / 运营委托）装配为一个可被栈集下发的整体，
# 并提供「声明式接管既有资源」与「交接时保留底层资源」两条链路的配置入口。
# ============================================================================

# ---------------------------------------------------------------------------
# 日志底座
# ---------------------------------------------------------------------------
# VPC 流日志投递目的地：LTS 日志组 + 日志流。
# ---------------------------------------------------------------------------

resource "huaweicloud_lts_group" "baseline" {
  group_name  = "${var.project_name}-baseline-logs"
  ttl_in_days = var.log_retention_days

  tags = var.tags
}

resource "huaweicloud_lts_stream" "baseline" {
  group_id    = huaweicloud_lts_group.baseline.id
  stream_name = "${var.project_name}-baseline-vpc-flowlog"
  ttl_in_days = var.log_retention_days

  tags = var.tags
}

# ---------------------------------------------------------------------------
# 网络基线
# ---------------------------------------------------------------------------

module "baseline_network" {
  source = "./modules/baseline-network"

  name_prefix   = var.project_name
  vpc_cidr      = var.vpc_cidr
  subnet_cidr   = var.subnet_cidr
  log_group_id  = huaweicloud_lts_group.baseline.id
  log_stream_id = huaweicloud_lts_stream.baseline.id
  tags          = var.tags
}

# ---------------------------------------------------------------------------
# 运营委托
# ---------------------------------------------------------------------------
# 需提供可代入本委托的管理账号 domain name；
# 未配置时跳过创建（委托无法凭空生成信任关系）。
# ---------------------------------------------------------------------------

module "baseline_agency" {
  source = "./modules/baseline-agency"

  count = var.agency_trusted_account_id != "" ? 1 : 0

  name_prefix         = var.project_name
  trusted_domain_name = var.agency_trusted_account_id
  description         = "Baseline operations agency for the landing zone governance"
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# 区域访问护栏
# ---------------------------------------------------------------------------
# 护栏需要组织级权限：组织策略直管要求调用者具备组织管理权限，
# 托管护栏要求资源治理中心已在当前账号开通落地环境。
# 因此护栏由独立开关控制，且在未提供挂载目标时整体不实例化——
# 其余基线（日志、网络、委托、通知、栈集）不受影响，可先行落地。
# ---------------------------------------------------------------------------

module "region_guardrail" {
  source = "./modules/region-guardrail"

  count = (var.enable_region_guardrail && (var.target_organizational_unit_id != "" || var.organization_root_id != "")) ? 1 : 0

  name_prefix                   = var.project_name
  approved_regions              = var.approved_regions
  target_organizational_unit_id = var.target_organizational_unit_id
  organization_root_id          = var.organization_root_id

  use_managed_guardrail = var.guardrail_mode == "managed_guardrail"

  # 组织策略直管路径：先试运行评估影响面，再正式挂载
  enable_dry_run           = var.guardrail_mode == "organizations_policy"
  dry_run_target_entity_id = var.dry_run_target_entity_id

  # 托管护栏路径：护栏标识与参数由资源治理中心内置策略定义
  managed_guardrail_identifier = var.managed_guardrail_identifier
  managed_guardrail_parameters = var.managed_guardrail_parameters

  tags = var.tags
}

# ---------------------------------------------------------------------------
# 治理告警通知
# ---------------------------------------------------------------------------
# 治理动作失败 / 栈集下发异常 / 资源基线漂移的邮件通知通道。
# ---------------------------------------------------------------------------

resource "huaweicloud_smn_topic" "governance" {
  name         = "${var.project_name}-governance-alerts"
  display_name = "Landing zone governance alerts"
  introduction = "Notifications for landing zone governance events"

  tags = var.tags
}

resource "huaweicloud_smn_subscription" "governance" {
  count = length(var.notification_recipients) > 0 ? 1 : 0

  topic_urn = huaweicloud_smn_topic.governance.topic_urn
  protocol  = var.notification_protocol
  endpoint  = var.notification_recipients[0]
  remark    = "Landing zone governance alert recipients"
}

# ---------------------------------------------------------------------------
# 资源栈集
# ---------------------------------------------------------------------------
# 栈集把基线模板批量下发到多个目标账号与多个区域。
# 模板为 Terraform HCL，由栈集服务在部署时注入 provider 配置。
# ---------------------------------------------------------------------------

resource "huaweicloud_rfs_stack_set" "baseline" {
  count = var.enable_stack_set ? 1 : 0

  stack_set_name        = local.stack_set_name
  stack_set_description = "Baseline governance stack set for multi-account rollout"
  template_uri          = local.stack_set_template_uri
  template_body         = local.stack_set_template_body
  permission_model      = var.stack_set_permission_model

  # 模板内容变更后，服务端不支持对既有栈集原地更新模板，
  # provider 在 plan 阶段会直接报错「template_body can't be updated」。
  # 打开该开关后，同样的变更会转为「销毁旧栈集 + 重建」，
  # 变更得以完成，但要注意替换会中断该栈集上已有的下发实例。
  enable_force_new = var.stack_set_enable_force_new

  # 栈集服务代入「管理委托」执行下发动作；
  # 自管模式下还需「被管理委托」用于目标账号侧的接入，两者是两个不同的委托。
  # 调用身份只在服务托管模式下有意义，自管模式下传入会被判为多余参数。
  administration_agency_name = var.stack_set_administration_agency_name
  managed_agency_name        = var.stack_set_permission_model == "SELF_MANAGED" ? var.stack_set_managed_agency_name : null
  call_identity              = var.stack_set_permission_model == "SERVICE_MANAGED" ? var.stack_set_call_identity : null

  managed_operation {
    enable_parallel_operation = true
  }
}

resource "huaweicloud_rfs_stack_set_deployment" "baseline" {
  count = var.enable_stack_set ? 1 : 0

  stack_set_name = huaweicloud_rfs_stack_set.baseline[0].stack_set_name
  template_uri   = local.stack_set_template_uri
  template_body  = local.stack_set_template_body

  # 与栈集本体保持同一替换策略：模板变更时一并重建部署。
  enable_force_new = var.stack_set_enable_force_new

  # 栈集变量以 tfvars 格式传入：每行一个 key = "value"
  vars_body = join("\n", [
    for k, v in var.stack_set_vars : "${k} = ${jsonencode(v)}"
  ])

  deployment_targets {
    domain_ids = var.stack_set_target_account_ids
    regions    = var.stack_set_target_regions
  }

  operation_preferences {
    failure_tolerance_count = 1
    max_concurrent_count    = 1
    region_concurrency_type = "SEQUENTIAL"
    region_order            = var.stack_set_target_regions
  }
}

# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------

output "log_group_id" {
  description = "基线日志组 ID"
  value       = huaweicloud_lts_group.baseline.id
}

output "log_stream_id" {
  description = "基线日志流 ID"
  value       = huaweicloud_lts_stream.baseline.id
}

output "baseline_vpc_id" {
  description = "基线 VPC ID"
  value       = module.baseline_network.vpc_id
}

output "baseline_subnet_id" {
  description = "基线子网 ID"
  value       = module.baseline_network.subnet_id
}

output "baseline_flow_log_id" {
  description = "基线 VPC 流日志 ID"
  value       = module.baseline_network.flow_log_id
}

output "baseline_secgroup_id" {
  description = "收紧后的默认安全组 ID"
  value       = module.baseline_network.secgroup_id
}

output "baseline_agency_id" {
  description = "基线运营委托 ID"
  value       = length(module.baseline_agency) > 0 ? module.baseline_agency[0].agency_id : null
}

output "guardrail_mode" {
  description = "区域护栏落地路径"
  value       = length(module.region_guardrail) > 0 ? module.region_guardrail[0].guardrail_mode : null
}

output "guardrail_policy_id" {
  description = "区域护栏策略 ID"
  value       = length(module.region_guardrail) > 0 ? module.region_guardrail[0].organizations_policy_id : null
}

output "guardrail_dry_run_policy_id" {
  description = "区域护栏试运行策略 ID"
  value       = length(module.region_guardrail) > 0 ? module.region_guardrail[0].dry_run_policy_id : null
}

output "guardrail_managed_control_id" {
  description = "托管治理护栏 ID（托管护栏路径）"
  value       = length(module.region_guardrail) > 0 ? module.region_guardrail[0].managed_guardrail_id : null
}

output "governance_topic_urn" {
  description = "治理告警通知主题 URN"
  value       = huaweicloud_smn_topic.governance.topic_urn
}

output "stack_set_id" {
  description = "资源栈集 ID"
  value       = var.enable_stack_set ? huaweicloud_rfs_stack_set.baseline[0].stack_set_id : null
}

output "stack_set_name" {
  description = "资源栈集名称"
  value       = var.enable_stack_set ? huaweicloud_rfs_stack_set.baseline[0].stack_set_name : null
}
