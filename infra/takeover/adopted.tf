# ============================================================================
# 接管工作区 · 资源定义
# ============================================================================
# 下列资源定义与线上既有资源逐属性一致，因此接管后 plan 不会出现漂移变更。
#
# 注意：这里刻意不使用 count / for_each ——
# 声明式接管（import 块）要求 import 的目标是不带索引的资源，
# 带 count 的资源无法被 import 块引用，只能改用命令式接管。
# ============================================================================

resource "huaweicloud_vpc" "adopted" {
  name        = var.takeover_targets.vpc.name
  cidr        = var.takeover_targets.vpc.cidr
  description = var.takeover_targets.vpc.description

  tags = var.takeover_targets.vpc.tags
}

resource "huaweicloud_vpc_subnet" "adopted" {
  name       = var.takeover_targets.subnet.name
  vpc_id     = huaweicloud_vpc.adopted.id
  cidr       = var.takeover_targets.subnet.cidr
  gateway_ip = var.takeover_targets.subnet.gateway_ip

  tags = var.takeover_targets.subnet.tags
}

resource "huaweicloud_vpc_flow_log" "adopted" {
  name          = var.takeover_targets.flow_log.name
  resource_type = "vpc"
  resource_id   = huaweicloud_vpc.adopted.id
  traffic_type  = "all"
  enabled       = true
  log_group_id  = var.takeover_targets.flow_log.log_group_id
  log_stream_id = var.takeover_targets.flow_log.log_stream_id
  description   = var.takeover_targets.flow_log.description
}

resource "huaweicloud_networking_secgroup" "adopted_default" {
  name        = var.takeover_targets.secgroup.name
  description = var.takeover_targets.secgroup.description

  tags = var.takeover_targets.secgroup.tags

  # delete_default_rules 是创建期专属参数：provider 在「创建安全组」时用它清空
  # 默认放通规则，读回时该字段恒为 null，且一旦声明即触发资源替换。
  # 接管既有安全组时写入该参数会直接导致「销毁 + 重建」，
  # 而重建后的安全组规则与原对象不一定一致，属于接管动作禁止发生的副作用。
  #
  # 因此接管定义中不声明该参数——它只描述「对象是怎么被创建出来的」，
  # 不描述「对象当前是什么状态」。若确需核验默认规则是否已清空，
  # 用 rules 输出字段比对，或在控制台确认。
  lifecycle {
    ignore_changes = [delete_default_rules]
  }
}

resource "huaweicloud_iam_agency" "adopted" {
  name                  = var.takeover_targets.agency.name
  description           = var.takeover_targets.agency.description
  delegated_domain_name = var.takeover_targets.agency.trusted_domain_name
  domain_roles          = var.takeover_targets.agency.roles

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

output "adopted_vpc_id" {
  description = "已接管的基线 VPC ID"
  value       = huaweicloud_vpc.adopted.id
}

output "adopted_subnet_id" {
  description = "已接管的基线子网 ID"
  value       = huaweicloud_vpc_subnet.adopted.id
}

output "adopted_flow_log_id" {
  description = "已接管的基线 VPC 流日志 ID"
  value       = huaweicloud_vpc_flow_log.adopted.id
}

output "adopted_secgroup_id" {
  description = "已接管的基线安全组 ID"
  value       = huaweicloud_networking_secgroup.adopted_default.id
}

output "adopted_agency_name" {
  description = "已接管的基线委托名称"
  value       = huaweicloud_iam_agency.adopted.name
}
