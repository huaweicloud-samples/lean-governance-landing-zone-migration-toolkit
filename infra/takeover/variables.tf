# ============================================================================
# 接管工作区 · 变量
# ============================================================================
# 本目录是一个独立的工作区，用于把既有基线资源纳入 Terraform 状态。
# 它与主装配目录互不引用：主装配负责「从零创建」，本目录负责「接管既有」。
#
# 使用步骤：
#   1. 在本目录执行 terraform init；
#   2. 按 takeover_targets 的结构填入线上既有资源的真实属性（属性必须逐项一致）；
#   3. 取消 import-blocks.tf 中对应 import 块的注释，并填入各资源的真实标识；
#   4. 执行 terraform plan，期望输出为
#      「N to import, 0 to add, 0 to change, 0 to destroy」；
#   5. 接管成功后删除 import 块（它是临时的接管声明，不是长期配置）。
# ============================================================================

variable "region" {
  description = "华为云区域"
  type        = string
  default     = "cn-north-4"
}

variable "takeover_targets" {
  description = <<-EOT
    待接管资源的真实属性集合。属性须与线上状态逐项一致，否则接管后 plan 会出现漂移变更。

    填写方式：
      - name / cidr / description 等标量属性：直接填线上控制台显示的值；
      - tags：填线上完整的标签集合（含自动生成的 Name 键），漏填或多填都会产生漂移；
      - 委托的 roles：填线上委托详情中「权限」列表的角色名。
  EOT
  type = object({
    vpc = object({
      name        = string
      cidr        = string
      description = string
      tags        = map(string)
    })
    subnet = object({
      name       = string
      cidr       = string
      gateway_ip = string
      tags       = map(string)
    })
    flow_log = object({
      name          = string
      description   = string
      log_group_id  = string
      log_stream_id = string
    })
    secgroup = object({
      name        = string
      description = string
      tags        = map(string)
    })
    agency = object({
      name                = string
      description         = string
      trusted_domain_name = string
      roles               = list(string)
    })
  })
}
