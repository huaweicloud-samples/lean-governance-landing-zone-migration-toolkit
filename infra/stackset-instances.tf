# ============================================================================
# 栈集实例下发
# ============================================================================
# 栈集定义与栈集部署只解决「模板给谁、部署到哪」，实例本身需要单独创建。
# 本文件用 terraform_data + local-exec 把「创建实例」接入 Terraform 生命周期：
#   apply  → 调用脚本创建实例，目标账号中真实出现基线资源；
#   destroy → 调用脚本删除实例。
#
# 这样多账号下发链路才是完整可复现的一键操作，
# 而不是「栈集建好了但目标账号里什么都没有」。
#
# 脚本路径相对本文件所在目录解析，栈集名称取自 local，
# 与主装配里创建栈集用的是同一个名称，避免两处定义漂移。
# ============================================================================

locals {
  stack_set_name = "${var.project_name}-baseline"

  stack_set_target_accounts = join(",", var.stack_set_target_account_ids)
  stack_set_target_regions  = join(",", var.stack_set_target_regions)

  # 模板来源二选一：
  #   给了文件路径 → 模板内容随栈集一并提交，不必额外准备可被读取的对象存储桶；
  #   只给了地址   → 从该地址拉取模板，地址须可被栈集服务读取。
  stack_set_template_uri  = var.stack_set_template_file == "" ? var.stack_set_template_url : null
  stack_set_template_body = var.stack_set_template_file == "" ? null : file(var.stack_set_template_file)
}

resource "terraform_data" "stack_set_instances" {
  count = var.enable_stack_set ? 1 : 0

  # 下发参数：写入 input，output 自动取 input 的值；
  # 销毁阶段的 provisioner 只能引用本资源的属性，不能引用配置中的其他值。
  input = {
    stack_set_name = local.stack_set_name
    account_ids    = local.stack_set_target_accounts
    regions        = local.stack_set_target_regions
  }

  # 影响下发结果的参数：变化时替换本资源，销毁旧实例并重新下发
  triggers_replace = {
    template_hash     = local.stack_set_template_body != null ? sha256(local.stack_set_template_body) : sha256(var.stack_set_template_url)
    vars_hash         = sha256(jsonencode(var.stack_set_vars))
    management_domain = var.agency_trusted_account_id
  }

  provisioner "local-exec" {
    when    = create
    command = "python3 ${path.module}/../scripts/rfs_stack_instance.py create --stack-set ${self.output.stack_set_name} --account-ids ${self.output.account_ids} --regions ${self.output.regions}"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "python3 ${path.module}/../scripts/rfs_stack_instance.py delete --stack-set ${self.output.stack_set_name} --account-ids ${self.output.account_ids} --regions ${self.output.regions}"
  }

  depends_on = [
    huaweicloud_rfs_stack_set_deployment.baseline,
  ]
}
