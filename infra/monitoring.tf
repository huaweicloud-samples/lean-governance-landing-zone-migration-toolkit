# ============================================================================
# 治理监控告警
# ============================================================================
# 治理链路有三类需要盯住的状态：
#   1. 下发失败   —— 栈集向目标账号下发基线时出错；
#   2. 下发超时   —— 下发耗时超出预期，说明有账号或区域卡住；
#   3. 护栏触发   —— 区域访问护栏拦截了越界调用，说明有配置漂移或越权尝试。
#
# 告警统一通过消息通知服务的治理主题下发到订阅者。
#
# 前提说明（重要）：
#   · 告警规则走应用运维管理的规则接口，该接口在部分区域 / 账号下会返回
#     AOM.02021500（服务端内部错误）。因此本组资源默认关闭，
#     由 enable_monitoring 显式开启；
#   · 开启前建议先用一条最小规则验证该区域可用，再批量启用。
#
# 不开启告警规则时，日志底座（日志组 + 日志流）与通知主题仍然正常工作，
# 治理事件可从日志与主题订阅中获取。
# ============================================================================

# ---------------------------------------------------------------------------
# 下发失败告警
# ---------------------------------------------------------------------------

resource "huaweicloud_aom_alarm_policy" "deployment_failure" {
  count = var.enable_monitoring ? 1 : 0

  alarm_rule_name        = "${var.project_name}-deployment-failure"
  alarm_rule_description = "Triggered when a baseline rollout reports a failure"
  alarm_rule_type        = "metric"
  alarm_rule_status      = "active"

  metric_alarm_spec {
    monitor_type = "SINGLE"

    trigger_conditions {
      metric_name      = "stack_set_operation_failures"
      metric_namespace = "SYS.RFS"
      operator         = "GT"
      thresholds       = { "300" = "0" }
      trigger_interval = "300"
      trigger_times    = 1
      aggregation_type = "average"
    }
  }

  alarm_notifications {
    notification_type = "NOTIFICATION"
    route_group_rule  = huaweicloud_smn_topic.governance.topic_urn
  }
}

# ---------------------------------------------------------------------------
# 下发超时告警
# ---------------------------------------------------------------------------

resource "huaweicloud_aom_alarm_policy" "deployment_timeout" {
  count = var.enable_monitoring ? 1 : 0

  alarm_rule_name        = "${var.project_name}-deployment-timeout"
  alarm_rule_description = "Triggered when a baseline rollout exceeds the expected duration"
  alarm_rule_type        = "metric"
  alarm_rule_status      = "active"

  metric_alarm_spec {
    monitor_type = "SINGLE"

    trigger_conditions {
      metric_name      = "stack_set_operation_duration"
      metric_namespace = "SYS.RFS"
      operator         = "GT"
      thresholds       = { "300" = "600" }
      trigger_interval = "300"
      trigger_times    = 1
      aggregation_type = "average"
    }
  }

  alarm_notifications {
    notification_type = "NOTIFICATION"
    route_group_rule  = huaweicloud_smn_topic.governance.topic_urn
  }
}

# ---------------------------------------------------------------------------
# 护栏触发告警
# ---------------------------------------------------------------------------

resource "huaweicloud_aom_alarm_policy" "guardrail_triggered" {
  count = var.enable_monitoring ? 1 : 0

  alarm_rule_name        = "${var.project_name}-guardrail-triggered"
  alarm_rule_description = "Triggered when the region guardrail blocks a call"
  alarm_rule_type        = "metric"
  alarm_rule_status      = "active"

  metric_alarm_spec {
    monitor_type = "SINGLE"

    trigger_conditions {
      metric_name      = "control_violation_count"
      metric_namespace = "SYS.RGC"
      operator         = "GT"
      thresholds       = { "300" = "0" }
      trigger_interval = "300"
      trigger_times    = 1
      aggregation_type = "average"
    }
  }

  alarm_notifications {
    notification_type = "NOTIFICATION"
    route_group_rule  = huaweicloud_smn_topic.governance.topic_urn
  }
}

# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------

output "governance_alarm_rule_ids" {
  description = "治理告警规则 ID 列表"
  value = var.enable_monitoring ? [
    huaweicloud_aom_alarm_policy.deployment_failure[0].id,
    huaweicloud_aom_alarm_policy.deployment_timeout[0].id,
    huaweicloud_aom_alarm_policy.guardrail_triggered[0].id,
  ] : []
}
