# ============================================================================
# Provider 与版本约束
# ============================================================================

terraform {
  required_version = ">= 1.7"

  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = ">= 1.97.0"
    }
  }

  # 生产环境建议将状态文件存储到 OBS 桶（通过 terraform backend 配置，
  # endpoint 指向 obs.<region>.myhuaweicloud.com；华为云 Terraform provider
  # 当前无原生 OBS backend，可改用本地/远程 backend 或对象存储兼容方案）。
}

# ============================================================================
# Provider 配置
# ============================================================================
# 访问凭据从环境变量读取：
#   export HW_ACCESS_KEY="<your-access-key>"
#   export HW_SECRET_KEY="<your-secret-key>"
# 使用 IAM Token 时追加：
#   export HW_SECURITY_TOKEN="<your-security-token>"
# ============================================================================

provider "huaweicloud" {
  region = var.region
}
