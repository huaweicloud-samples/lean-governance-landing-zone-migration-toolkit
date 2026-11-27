
# ============================================================================
# Provider 约束
# ============================================================================

terraform {
  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = ">= 1.97.0"
    }
  }
}
