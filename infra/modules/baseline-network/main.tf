# ============================================================================
# 基线网络模块
# ============================================================================
# 为每个受治理账号创建统一的网络基线：
#   - 独立 VPC（账号级隔离边界）
#   - 子网
#   - VPC 流日志（投递到 LTS 日志组/日志流）
#   - 默认安全组收紧（清空默认入站/出站规则）
# ============================================================================

variable "name_prefix" {
  description = "资源名称前缀"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR 网段"
  type        = string
}

variable "subnet_cidr" {
  description = "子网 CIDR 网段"
  type        = string
}

variable "log_group_id" {
  description = "流日志投递的 LTS 日志组 ID"
  type        = string
}

variable "log_stream_id" {
  description = "流日志投递的 LTS 日志流 ID"
  type        = string
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------

resource "huaweicloud_vpc" "baseline" {
  name        = "${var.name_prefix}-vpc"
  cidr        = var.vpc_cidr
  description = "Account baseline VPC managed by the landing zone governance"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

# ---------------------------------------------------------------------------
# 子网
# ---------------------------------------------------------------------------

resource "huaweicloud_vpc_subnet" "baseline" {
  name       = "${var.name_prefix}-subnet"
  vpc_id     = huaweicloud_vpc.baseline.id
  cidr       = var.subnet_cidr
  gateway_ip = cidrhost(var.subnet_cidr, 1)

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-subnet"
  })
}

# ---------------------------------------------------------------------------
# VPC 流日志
# ---------------------------------------------------------------------------
# 目的地为 LTS 日志组 + 日志流，而非集中对象存储桶。
# 采集流量类型为全量（all），保证审计链路完整。
# ---------------------------------------------------------------------------

resource "huaweicloud_vpc_flow_log" "baseline" {
  name          = "${var.name_prefix}-flowlog"
  resource_type = "vpc"
  resource_id   = huaweicloud_vpc.baseline.id
  traffic_type  = "all"
  enabled       = true
  log_group_id  = var.log_group_id
  log_stream_id = var.log_stream_id
  description   = "Baseline VPC flow log for the landing zone governance"

}

# ---------------------------------------------------------------------------
# 默认安全组收紧
# ---------------------------------------------------------------------------
# delete_default_rules = true 清空默认安全组的默认放通规则，
# 使该 VPC 的默认安全组不再提供隐式全通放行。
# ---------------------------------------------------------------------------

resource "huaweicloud_networking_secgroup" "default_tightened" {
  name                  = "${var.name_prefix}-default-sg-tightened"
  description           = "Tightened default security group for the baseline VPC"
  delete_default_rules  = true
  enterprise_project_id = null

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-default-sg-tightened"
  })
}

# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------

output "vpc_id" {
  description = "基线 VPC ID"
  value       = huaweicloud_vpc.baseline.id
}

output "vpc_name" {
  description = "基线 VPC 名称"
  value       = huaweicloud_vpc.baseline.name
}

output "subnet_id" {
  description = "基线子网 ID"
  value       = huaweicloud_vpc_subnet.baseline.id
}

output "flow_log_id" {
  description = "基线 VPC 流日志 ID"
  value       = huaweicloud_vpc_flow_log.baseline.id
}

output "secgroup_id" {
  description = "收紧后的默认安全组 ID"
  value       = huaweicloud_networking_secgroup.default_tightened.id
}
