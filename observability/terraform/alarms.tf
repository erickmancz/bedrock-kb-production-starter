################################################################################
# Alarms.
#
# Three alarms that map to actual on-call signals:
#
#   1. Ingestion failures > threshold — your KB is silently going stale
#   2. Retrieve p99 latency above threshold — users are waiting too long
#   3. Server errors on Retrieve — Bedrock or OpenSearch is unhappy
#
# Each one routes to var.alarm_sns_topic_arn if set, otherwise creates the
# alarm without a notification target (still actionable from the console).
################################################################################

locals {
  alarm_actions = var.alarm_sns_topic_arn == "" ? [] : [var.alarm_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "ingestion_failures" {
  alarm_name          = "${local.name_prefix}-kb-ingestion-failures"
  alarm_description   = "Documents are failing to ingest into the Knowledge Base. The KB is going stale relative to the source bucket."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = var.ingestion_failure_alarm_threshold
  treat_missing_data  = "notBreaching"

  metric_name = "DocumentsFailedToIngest"
  namespace   = "AWS/Bedrock"
  statistic   = "Sum"
  period      = 300

  dimensions = {
    KnowledgeBaseId = var.knowledge_base_id
    DataSourceId    = var.data_source_id
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "retrieve_latency_p99" {
  alarm_name          = "${local.name_prefix}-kb-retrieve-latency-p99"
  alarm_description   = "Retrieve API p99 latency exceeded threshold. Likely causes: cold OCU scale-up, oversized chunks, or model throttling."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = var.retrieval_latency_p99_threshold_ms
  treat_missing_data  = "notBreaching"

  metric_name        = "InvocationLatency"
  namespace          = "AWS/Bedrock"
  extended_statistic = "p99"
  period             = 300

  dimensions = {
    Operation       = "Retrieve"
    KnowledgeBaseId = var.knowledge_base_id
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "retrieve_server_errors" {
  alarm_name          = "${local.name_prefix}-kb-retrieve-server-errors"
  alarm_description   = "Retrieve API returned 5xx. Bedrock or the underlying OpenSearch collection is failing."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  treat_missing_data  = "notBreaching"

  metric_name = "InvocationServerErrors"
  namespace   = "AWS/Bedrock"
  statistic   = "Sum"
  period      = 300

  dimensions = {
    Operation       = "Retrieve"
    KnowledgeBaseId = var.knowledge_base_id
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}
