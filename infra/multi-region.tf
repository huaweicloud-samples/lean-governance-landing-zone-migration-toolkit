# ============================================================================
# 多区域 provider 别名
# ============================================================================
# 同一套基线需要在多个区域落地时，为每个区域声明一个 provider 别名，
# 模块通过显式传入 provider 的方式使用对应区域的能力。
#
# 由 enable_multi_region 控制：默认关闭。开启后，除主区域基线外，
# 会在 north / east 两个区域各落地一套独立基线（网络 + 日志底座）。
#
# 区域间网段可重复（不同区域的 VPC 互不可见），但同一区域内不得重复，
# 因此附加区域使用 additional_vpc_cidr / additional_subnet_cidr，
# 与主区域的 vpc_cidr / subnet_cidr 天然错开。
# ============================================================================

provider "huaweicloud" {
  alias  = "north"
  region = var.multi_region_north_region
}

provider "huaweicloud" {
  alias  = "east"
  region = var.multi_region_east_region
}

# ---------------------------------------------------------------------------
# 多区域基线下发
# ---------------------------------------------------------------------------
# 每个区域的基线资源彼此独立，日志底座按区域各自创建。
# ---------------------------------------------------------------------------

module "baseline_network_north" {
  source = "./modules/baseline-network"

  count = var.enable_multi_region ? 1 : 0

  providers = {
    huaweicloud = huaweicloud.north
  }

  name_prefix   = "${var.project_name}-north"
  vpc_cidr      = var.secondary_vpc_cidr
  subnet_cidr   = var.secondary_subnet_cidr
  log_group_id  = huaweicloud_lts_group.north[0].id
  log_stream_id = huaweicloud_lts_stream.north[0].id
  tags          = var.tags
}

module "baseline_network_east" {
  source = "./modules/baseline-network"

  count = var.enable_multi_region ? 1 : 0

  providers = {
    huaweicloud = huaweicloud.east
  }

  name_prefix   = "${var.project_name}-east"
  vpc_cidr      = var.secondary_vpc_cidr
  subnet_cidr   = var.secondary_subnet_cidr
  log_group_id  = huaweicloud_lts_group.east[0].id
  log_stream_id = huaweicloud_lts_stream.east[0].id
  tags          = var.tags
}

resource "huaweicloud_lts_group" "north" {
  count = var.enable_multi_region ? 1 : 0

  provider = huaweicloud.north

  group_name  = "${var.project_name}-north-logs"
  ttl_in_days = var.log_retention_days

  tags = var.tags
}

resource "huaweicloud_lts_stream" "north" {
  count = var.enable_multi_region ? 1 : 0

  provider = huaweicloud.north

  group_id    = huaweicloud_lts_group.north[0].id
  stream_name = "${var.project_name}-north-vpc-flowlog"
  ttl_in_days = var.log_retention_days

  tags = var.tags
}

resource "huaweicloud_lts_group" "east" {
  count = var.enable_multi_region ? 1 : 0

  provider = huaweicloud.east

  group_name  = "${var.project_name}-east-logs"
  ttl_in_days = var.log_retention_days

  tags = var.tags
}

resource "huaweicloud_lts_stream" "east" {
  count = var.enable_multi_region ? 1 : 0

  provider = huaweicloud.east

  group_id    = huaweicloud_lts_group.east[0].id
  stream_name = "${var.project_name}-east-vpc-flowlog"
  ttl_in_days = var.log_retention_days

  tags = var.tags
}

# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------

output "multi_region_vpc_ids" {
  description = "附加区域的基线 VPC ID（按 north / east 顺序）"
  value = var.enable_multi_region ? [
    module.baseline_network_north[0].vpc_id,
    module.baseline_network_east[0].vpc_id,
  ] : []
}
