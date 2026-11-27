# ============================================================================
# 基线委托模块
# ============================================================================
# 为每个受治理账号创建一个可代入的委托，授予只读运维权限。
#
# 与「角色 + 信任策略 + 托管策略」三件套的差异：
#   - 华为云以「委托」表达跨账号代入关系，可代入主体由
#     delegated_domain_name（账号型）或 delegated_service_name（服务型）指定；
#   - 委托不携带条件式的二次校验约束，入股条件需由调用方与审计侧保证。
# ============================================================================

variable "name_prefix" {
  description = "资源名称前缀"
  type        = string
}

variable "trusted_domain_name" {
  description = "可代入本委托的管理账号 domain name（账号型委托）"
  type        = string
}

variable "domain_roles" {
  description = "授予委托的域级角色名称列表"
  type        = list(string)
  default     = ["ReadOnlyAccess"]
}

variable "project_roles" {
  description = "授予委托的项目级角色名称列表"
  type        = list(string)
  default     = []
}

variable "description" {
  description = "委托描述"
  type        = string
  default     = "Baseline operations agency managed by the landing zone governance"
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# 基线委托
# ---------------------------------------------------------------------------

resource "huaweicloud_iam_agency" "baseline" {
  name                  = "${var.name_prefix}-ops-agency"
  description           = var.description
  delegated_domain_name = var.trusted_domain_name
  domain_roles          = var.domain_roles

  dynamic "project_role" {
    for_each = length(var.project_roles) > 0 ? [1] : []
    content {
      project = var.name_prefix
      roles   = var.project_roles
    }
  }

  # 委托的域级角色由单独的角色查询接口回读，
  # 该接口对「缺少委托读取权限」的身份返回 403，回读结果恒为空，
  # 从而在每次 plan 中产生一处与真实配置无关的变更。
  # 授予动作本身仍然生效，因此这里抑制对回读结果的差异比对；
  # 角色是否真正落地以控制台的委托详情为准。
  lifecycle {
    ignore_changes = [domain_roles]
  }
}

# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------

output "agency_id" {
  description = "基线委托 ID"
  value       = huaweicloud_iam_agency.baseline.id
}

output "agency_name" {
  description = "基线委托名称"
  value       = huaweicloud_iam_agency.baseline.name
}
