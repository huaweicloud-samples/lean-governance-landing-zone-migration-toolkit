# ============================================================================
# 敏感参数外置
# ============================================================================
# 基线配置里凡是需要保密的取值（访问凭据、令牌、加密口令），
# 一律不写进模板参数与变量文件，改为存放在密钥管理服务中，
# 由部署侧按需读取。
#
# 这样做的收益：
#   · 基线模板可以安全地纳入版本管理，评审时不必担心泄露；
#   · 密钥的轮换与吊销不需要改动基线定义；
#   · 密钥的访问被记录为审计事件，谁在什么时间取了哪个密钥可追溯。
#
# 读取方式见 ../scripts/ 中的读取示例。
# ============================================================================

# ---------------------------------------------------------------------------
# 密钥容器
# ---------------------------------------------------------------------------
# 通用类型的密钥存放非结构化的配置取值；版本号用于区分轮次。
# 专用类型的密钥用于存放特定服务的原生凭据格式。
# ---------------------------------------------------------------------------

resource "huaweicloud_csms_secret" "baseline" {
  count = var.enable_sensitive_params ? 1 : 0

  name                  = "${var.project_name}-baseline-sensitive"
  secret_type           = "COMMON"
  secret_text           = var.sensitive_secret_text
  kms_key_id            = var.sensitive_kms_key_id
  expire_time           = var.sensitive_expire_time
  description           = "Sensitive baseline parameters, read at deployment time"
  enterprise_project_id = null
}

# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------
# 只输出密钥标识与版本，不输出明文取值。
# ---------------------------------------------------------------------------

output "sensitive_secret_id" {
  description = "敏感参数所在密钥的标识"
  value       = var.enable_sensitive_params ? huaweicloud_csms_secret.baseline[0].secret_id : null
}

output "sensitive_latest_version" {
  description = "敏感参数当前生效版本"
  value       = var.enable_sensitive_params ? huaweicloud_csms_secret.baseline[0].latest_version : null
}
