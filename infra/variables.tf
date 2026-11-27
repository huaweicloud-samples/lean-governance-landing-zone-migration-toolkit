# ============================================================================
# 变量定义
# ============================================================================

variable "region" {
  description = "华为云区域"
  type        = string
  default     = "cn-north-4"
}

variable "project_name" {
  description = "项目名称，用于资源命名前缀"
  type        = string
  default     = "landing-zone-governance"
}

variable "vpc_cidr" {
  description = "基线 VPC 的 CIDR 网段"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "基线子网的 CIDR 网段"
  type        = string
  default     = "10.0.1.0/24"
}

variable "secondary_vpc_cidr" {
  description = "附加区域基线 VPC 的 CIDR 网段。与主区域网段错开，避免同区域网段冲突"
  type        = string
  default     = "10.1.0.0/16"
}

variable "secondary_subnet_cidr" {
  description = "附加区域基线子网的 CIDR 网段"
  type        = string
  default     = "10.1.1.0/24"
}

variable "log_retention_days" {
  description = "日志组与日志流保留天数"
  type        = number
  default     = 30
}

variable "approved_regions" {
  description = "区域访问护栏允许的地域列表"
  type        = list(string)
  default     = ["cn-north-4", "cn-east-3"]
}

variable "notification_recipients" {
  description = "治理告警邮件订阅地址列表"
  type        = list(string)
  default     = []
}

variable "notification_protocol" {
  description = "告警订阅协议（email / sms / webhook 等）"
  type        = string
  default     = "email"
}

variable "agency_trusted_account_id" {
  description = "可代入基线委托的可信管理账号域名（形如 hwcdnhw00000000）。留空则不创建委托"
  type        = string
  default     = ""
}

variable "organization_root_id" {
  description = "组织根节点 ID，用于挂载组织级策略"
  type        = string
  default     = ""
}

variable "target_organizational_unit_id" {
  description = "区域护栏策略挂载的目标组织单元 ID"
  type        = string
  default     = ""
}

variable "enable_region_guardrail" {
  description = "是否部署区域访问护栏。需具备组织管理权限；无权限时置 false 可先落地其余基线"
  type        = bool
  default     = true
}

variable "guardrail_mode" {
  description = "护栏落地路径：organizations_policy = 组织策略直管（可在正式挂载前先做试运行）；managed_guardrail = 使用资源治理中心托管护栏"
  type        = string
  default     = "organizations_policy"

  validation {
    condition     = contains(["organizations_policy", "managed_guardrail"], var.guardrail_mode)
    error_message = "guardrail_mode 只能取 organizations_policy 或 managed_guardrail。"
  }
}

variable "dry_run_target_entity_id" {
  description = "组织策略试运行的目标实体 ID。填写后先做试运行评估影响面，确认无误再正式挂载"
  type        = string
  default     = ""
}

variable "managed_guardrail_identifier" {
  description = "托管治理护栏标识（guardrail_mode = managed_guardrail 时生效）"
  type        = string
  default     = "RGC.REGION_LIMIT"
}

variable "managed_guardrail_parameters" {
  description = "托管治理护栏参数（guardrail_mode = managed_guardrail 时生效，JSON 字符串）"
  type        = string
  default     = "{}"
}

variable "enable_stack_set" {
  description = "是否创建资源栈集并向目标账号下发基线"
  type        = bool
  default     = false
}

variable "stack_set_target_account_ids" {
  description = "栈集下发的目标账号 ID 列表"
  type        = list(string)
  default     = []
}

variable "stack_set_target_regions" {
  description = "栈集下发的目标区域列表"
  type        = list(string)
  default     = ["cn-north-4"]
}

variable "stack_set_template_url" {
  description = "基线模板地址（OBS 内网可读地址，须为 VirtualHost 域名形式）。与 stack_set_template_file 二选一"
  type        = string
  default     = ""
}

variable "stack_set_template_file" {
  description = "基线模板文件路径（相对本目录）。填写后模板内容随栈集一并提交，无需额外的对象存储桶；与 stack_set_template_url 二选一"
  type        = string
  default     = ""
}

variable "stack_set_vars" {
  description = "栈集变量（tfvars 格式的键值对）"
  type        = map(string)
  default     = {}
}

variable "stack_set_permission_model" {
  description = "栈集权限模型：SELF_MANAGED = 自管模式（需同时提供管理委托与被管理委托）；SERVICE_MANAGED = 服务托管模式（无需用户委托，但要求当前账号属于一个组织）"
  type        = string
  default     = "SELF_MANAGED"

  validation {
    condition     = contains(["SELF_MANAGED", "SERVICE_MANAGED"], var.stack_set_permission_model)
    error_message = "stack_set_permission_model 只能取 SELF_MANAGED 或 SERVICE_MANAGED。"
  }
}

variable "stack_set_administration_agency_name" {
  description = "管理委托名称。栈集服务代入该委托执行下发动作，必须提供"
  type        = string
  default     = ""
}

variable "stack_set_managed_agency_name" {
  description = "被管理委托名称。权限模型为 SELF_MANAGED 时必须提供"
  type        = string
  default     = ""
}

variable "stack_set_call_identity" {
  description = "栈集调用身份：SELF = 以栈集所有者身份调用；DELEGATED_ADMIN = 以委托的管理员身份调用"
  type        = string
  default     = "SELF"
}

variable "stack_set_enable_force_new" {
  description = <<-EOT
    栈集模板变更时的替换策略。

    模板内容提交后，服务端不支持对既有栈集原地更新模板，
    provider 在 plan 阶段会直接报错「template_body can't be updated」。
    取值为 "true" 时，同样的变更转为「销毁旧栈集与部署 + 重建」，
    变更得以完成；留空则保持 provider 默认行为（变更时报错，等待人工决策）。

    注意：替换会中断该栈集上已存在的下发实例，变更前应确认目标账号侧无需保留当前实例。
  EOT
  type        = string
  default     = ""
}

variable "tags" {
  description = "统一附加到资源的标签"
  type        = map(string)
  default = {
    ManagedBy = "landing-zone-governance"
  }
}

variable "enable_sensitive_params" {
  description = "是否创建存放敏感参数的密钥容器"
  type        = bool
  default     = false
}

variable "sensitive_secret_text" {
  description = "敏感参数的初始取值（明文写入后由密钥服务托管）"
  type        = string
  default     = ""
  sensitive   = true
}

variable "sensitive_kms_key_id" {
  description = "加密敏感参数所用的客户主密钥 ID"
  type        = string
  default     = ""
}

variable "sensitive_expire_time" {
  description = "敏感参数过期时间戳（秒）"
  type        = number
  default     = 0
}

variable "enable_monitoring" {
  description = "是否创建治理告警规则。告警规则接口在部分区域会返回服务端内部错误，默认关闭；开启前建议先用单条规则验证该区域可用"
  type        = bool
  default     = false
}

variable "enable_multi_region" {
  description = "是否在附加区域各落地一套独立基线。开启后会在两个附加区域各创建一套网络基线与日志底座"
  type        = bool
  default     = false
}

variable "multi_region_north_region" {
  description = "附加区域一的区域标识"
  type        = string
  default     = "cn-north-4"
}

variable "multi_region_east_region" {
  description = "附加区域二的区域标识"
  type        = string
  default     = "cn-east-3"
}
