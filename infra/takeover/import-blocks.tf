# ============================================================================
# 接管工作区 · 接管声明
# ============================================================================
# import 块的 to 必须指向上面已声明的资源，id 为资源在云端的唯一标识。
#
# 各资源类型的接管标识格式（已实测确认）：
#   VPC             → <vpc_id>
#   子网            → <subnet_id>
#   VPC 流日志      → <flow_log_id>          （不带 VPC ID 前缀）
#   安全组          → <secgroup_id>
#   委托            → <agency_id>            （不是委托名称）
#   资源栈          → <stack_name>
#   LTS 日志组      → <group_id>
#   LTS 日志流      → <group_id>/<stream_id>
#
# 标识错误会导致接管失败或接管到错误对象：
#   - 流日志写成 <vpc_id>/<flow_log_id> → 报「远程对象不存在」；
#   - 委托写成委托名称 → 报「资源已被 Terraform 管理」或匹配到错误对象。
# ============================================================================

# import {
#   to = huaweicloud_vpc.adopted
#   id = "00000000-0000-0000-0000-000000000000"
# }
#
# import {
#   to = huaweicloud_vpc_subnet.adopted
#   id = "00000000-0000-0000-0000-000000000000"
# }
#
# import {
#   to = huaweicloud_vpc_flow_log.adopted
#   id = "00000000-0000-0000-0000-000000000000"
# }
#
# import {
#   to = huaweicloud_networking_secgroup.adopted_default
#   id = "00000000-0000-0000-0000-000000000000"
# }
#
# import {
#   to = huaweicloud_iam_agency.adopted
#   id = "00000000-0000-0000-0000-000000000000"
# }

# ---------------------------------------------------------------------------
# 批量接管
# ---------------------------------------------------------------------------
# 资源数量较多时，逐个 import 块维护麻烦，可改用命令式批量接管：
#
#   terraform import huaweicloud_vpc.adopted              <vpc_id>
#   terraform import huaweicloud_vpc_subnet.adopted        <subnet_id>
#   terraform import huaweicloud_networking_secgroup.adopted_default <secgroup_id>
#
# 命令式接管与声明式接管的效果相同：接管结果同样进入状态、同样受 plan 管控，
# 差别只在于声明不在版本库里，无法在代码评审中看到「本次接管了哪些对象」。
# 建议：首次接管用命令式（快速验证），固化到版本库后改用 import 块（可评审）。
#
# ---------------------------------------------------------------------------
# 接管后的零漂移校验
# ---------------------------------------------------------------------------
# terraform plan 期望输出：
#
#   Plan: 5 to import, 0 to add, 0 to change, 0 to destroy.
#
# 若出现 to change 或 to destroy，说明资源定义与线上状态不一致，
# 必须先修正定义属性（而不是直接 apply），否则会覆盖线上已有配置。
# 校验脚本见 ../../scripts/verify-takeover.sh。
# ---------------------------------------------------------------------------
