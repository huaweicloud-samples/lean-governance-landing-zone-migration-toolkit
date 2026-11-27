# ============================================================================
# 区域访问护栏模块
# ============================================================================
# 拒绝未授权地域上的全部调用，把治理边界收敛到白名单区域。
#
# 两种落地路径，均在本模块内给出：
#   路径 A —— 组织策略直管：策略内容完全由本仓库存写、随 Terraform 生命周期管理，
#             并可先做试运行验证影响面，再正式挂载到目标组织单元；
#   路径 B —— 托管治理护栏：交由资源治理中心的内置治理策略执行，
#             不需要跨账号的组织级权限。
#
# 两者的分工与「直接管理 vs 使用托管护栏」的选择依据，参见 docs/architecture.md。
# ============================================================================

variable "name_prefix" {
  description = "资源名称前缀"
  type        = string
}

variable "approved_regions" {
  description = "允许访问的地域列表"
  type        = list(string)
}

variable "target_organizational_unit_id" {
  description = "策略挂载的目标组织单元 ID（路径 A 使用）"
  type        = string
  default     = ""
}

variable "organization_root_id" {
  description = "组织根节点 ID（路径 A 挂载到根时使用）"
  type        = string
  default     = ""
}

variable "use_managed_guardrail" {
  description = "是否使用资源治理中心托管护栏（true = 路径 B，false = 路径 A）"
  type        = bool
  default     = false
}

variable "managed_guardrail_identifier" {
  description = "托管治理护栏标识（路径 B 使用）"
  type        = string
  default     = "RGC.REGION_LIMIT"
}

variable "managed_guardrail_parameters" {
  description = "托管治理护栏参数（路径 B 使用）"
  type        = string
  default     = "{}"
}

variable "enable_dry_run" {
  description = "路径 A：是否先执行策略试运行"
  type        = bool
  default     = true
}

variable "dry_run_target_entity_id" {
  description = "试运行的目标实体 ID"
  type        = string
  default     = ""
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# 路径 A —— 组织策略直管
# ---------------------------------------------------------------------------
# 策略内容与「拒绝未授权地域」的语义一一对应：
#   Effect = Deny，Action 与 Resource 覆盖全部调用，
#   条件键限定请求地域必须落在白名单内，否则拒绝。
# ---------------------------------------------------------------------------

locals {
  region_guardrail_content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyUnauthorizedRegions"
      Effect   = "Deny"
      Action   = "*"
      Resource = "*"
      Condition = {
        StringNotEquals = {
          "huaweicloud:RequestedRegion" = var.approved_regions
        }
      }
    }]
  })
}

resource "huaweicloud_organizations_policy" "region_guardrail" {
  count = var.use_managed_guardrail ? 0 : 1

  name        = "${var.name_prefix}-deny-unauthorized-regions"
  description = "Deny access to regions outside the approved list"
  type        = "SERVICE_CONTROL_POLICY"
  content     = local.region_guardrail_content

  tags = var.tags
}

resource "huaweicloud_organizations_policy_attach" "region_guardrail" {
  count = var.use_managed_guardrail ? 0 : 1

  policy_id = huaweicloud_organizations_policy.region_guardrail[0].id
  entity_id = var.target_organizational_unit_id != "" ? var.target_organizational_unit_id : var.organization_root_id
}

# ---------------------------------------------------------------------------
# 路径 A —— 试运行
# ---------------------------------------------------------------------------
# 试运行用于在正式挂载前评估策略对既有账号的影响面，
# 结果可作为是否正式挂载的决策依据。
# ---------------------------------------------------------------------------

resource "huaweicloud_organizations_dry_run_policy" "region_guardrail" {
  count = (!var.use_managed_guardrail && var.enable_dry_run && var.dry_run_target_entity_id != "") ? 1 : 0

  name        = "${var.name_prefix}-deny-unauthorized-regions-dry-run"
  description = "Dry run evaluation of the region guardrail before enforcement"
  type        = "SERVICE_CONTROL_POLICY"
  content     = local.region_guardrail_content
}

resource "huaweicloud_organizations_dry_run_policy_entity_attach" "region_guardrail" {
  count = (!var.use_managed_guardrail && var.enable_dry_run && var.dry_run_target_entity_id != "") ? 1 : 0

  policy_id = huaweicloud_organizations_dry_run_policy.region_guardrail[0].id
  entity_id = var.dry_run_target_entity_id
}

# ---------------------------------------------------------------------------
# 路径 B —— 资源治理中心托管护栏
# ---------------------------------------------------------------------------

resource "huaweicloud_rgc_control" "region_guardrail" {
  count = var.use_managed_guardrail ? 1 : 0

  identifier        = var.managed_guardrail_identifier
  target_identifier = var.target_organizational_unit_id
  parameters        = var.managed_guardrail_parameters
}

# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------

output "guardrail_mode" {
  description = "护栏落地路径（managed_guardrail / organizations_policy）"
  value       = var.use_managed_guardrail ? "managed_guardrail" : "organizations_policy"
}

output "organizations_policy_id" {
  description = "组织策略 ID（路径 A）"
  value       = var.use_managed_guardrail ? null : huaweicloud_organizations_policy.region_guardrail[0].id
}

output "dry_run_policy_id" {
  description = "试运行策略 ID（路径 A，启用试运行时）"
  value       = length(huaweicloud_organizations_dry_run_policy.region_guardrail) > 0 ? huaweicloud_organizations_dry_run_policy.region_guardrail[0].id : null
}

output "managed_guardrail_id" {
  description = "托管治理护栏 ID（路径 B）"
  value       = var.use_managed_guardrail ? huaweicloud_rgc_control.region_guardrail[0].id : null
}
