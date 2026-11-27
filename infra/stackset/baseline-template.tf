# ============================================================================
# 栈集基线模板
# ============================================================================
# 资源栈集的模板必须是 Terraform HCL，且不得声明 provider 配置块 ——
# 资源编排服务在部署时自动注入 provider 配置，手写占位符会导致部署失败。
#
# provider 来源必须是资源编排服务可检索的内部地址
# （huawei.com/provider/huaweicloud），并锁定版本；
# 用公共仓库地址会导致服务端检索版本列表失败，栈直接进入部署失败状态。
#
# 变量通过栈集的 vars 参数传入，格式为 HCL 的 tfvars 格式（键 = "值"），
# 不是 YAML 也不是 JSON。
#
# 块语法必须遵循 HCL2：块体内的属性与子块需换行书写，
# 单行块写法（如 variable "x" { type = string }）会被判为模板格式非法。
# ============================================================================

terraform {
  required_providers {
    huaweicloud = {
      source  = "huawei.com/provider/huaweicloud"
      version = "1.97.1"
    }
  }
}

# ---------------------------------------------------------------------------
# 变量
# ---------------------------------------------------------------------------

variable "name_prefix" {
  type    = string
  default = "landing-zone-governance"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "log_group_id" {
  type    = string
  default = ""
}

variable "log_stream_id" {
  type    = string
  default = ""
}

variable "trusted_domain_name" {
  type    = string
  default = ""
}

# ---------------------------------------------------------------------------
# 网络基线
# ---------------------------------------------------------------------------

resource "huaweicloud_vpc" "baseline" {
  name = "${var.name_prefix}-vpc"
  cidr = var.vpc_cidr

  tags = {
    ManagedBy = var.name_prefix
  }
}

resource "huaweicloud_vpc_subnet" "baseline" {
  name       = "${var.name_prefix}-subnet"
  vpc_id     = huaweicloud_vpc.baseline.id
  cidr       = var.subnet_cidr
  gateway_ip = cidrhost(var.subnet_cidr, 1)

  tags = {
    ManagedBy = var.name_prefix
  }
}

resource "huaweicloud_networking_secgroup" "default_tightened" {
  name                 = "${var.name_prefix}-default-sg-tightened"
  description          = "Tightened default security group for the baseline VPC"
  delete_default_rules = true

  tags = {
    ManagedBy = var.name_prefix
  }
}

# ---------------------------------------------------------------------------
# 流日志
# ---------------------------------------------------------------------------

resource "huaweicloud_vpc_flow_log" "baseline" {
  name          = "${var.name_prefix}-flowlog"
  resource_type = "vpc"
  resource_id   = huaweicloud_vpc.baseline.id
  traffic_type  = "all"
  enabled       = true
  log_group_id  = var.log_group_id
  log_stream_id = var.log_stream_id
}

# ---------------------------------------------------------------------------
# 运营委托
# ---------------------------------------------------------------------------

resource "huaweicloud_iam_agency" "baseline" {
  count = var.trusted_domain_name == "" ? 0 : 1

  name                  = "${var.name_prefix}-ops-agency"
  description           = "Baseline operations agency for the landing zone governance"
  delegated_domain_name = var.trusted_domain_name
  domain_roles          = ["ReadOnlyAccess"]
}

# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------

output "vpc_id" {
  value = huaweicloud_vpc.baseline.id
}

output "subnet_id" {
  value = huaweicloud_vpc_subnet.baseline.id
}
