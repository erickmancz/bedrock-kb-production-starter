output "dashboard_name" {
  description = "Name of the CloudWatch dashboard."
  value       = aws_cloudwatch_dashboard.kb.dashboard_name
}

output "dashboard_url" {
  description = "Direct console URL to the dashboard."
  value = format(
    "https://%s.console.aws.amazon.com/cloudwatch/home?region=%s#dashboards:name=%s",
    var.aws_region,
    var.aws_region,
    aws_cloudwatch_dashboard.kb.dashboard_name,
  )
}

output "alarm_arns" {
  description = "ARNs of the alarms created by this module."
  value = {
    ingestion_failures      = aws_cloudwatch_metric_alarm.ingestion_failures.arn
    retrieve_latency_p99    = aws_cloudwatch_metric_alarm.retrieve_latency_p99.arn
    retrieve_server_errors  = aws_cloudwatch_metric_alarm.retrieve_server_errors.arn
  }
}
