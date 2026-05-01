################################################################################
# Operational dashboard for the Knowledge Base.
#
# Three rows:
#   1. Retrieval — request count and latency (AWS/Bedrock metrics)
#   2. Ingestion — documents ingested vs. failed (AWS/Bedrock metrics)
#   3. Chunker — custom metrics from the chunker log group (only when wired up)
#
# All graphs share a 5-minute period, which is the granularity Bedrock
# emits at. Don't switch to 1-minute — you'll see flat-line gaps that
# look like outages but aren't.
################################################################################

locals {
  dashboard_body = jsonencode({
    widgets = concat(
      # ----- Row 1: retrieval -----
      [
        {
          type   = "metric"
          x      = 0
          y      = 0
          width  = 12
          height = 6
          properties = {
            title  = "Retrieve invocations"
            region = var.aws_region
            view   = "timeSeries"
            stat   = "Sum"
            period = 300
            metrics = [
              ["AWS/Bedrock", "Invocations", "Operation", "Retrieve",
                "KnowledgeBaseId", var.knowledge_base_id],
              [".",            "InvocationClientErrors", ".", ".", ".", "."],
              [".",            "InvocationServerErrors", ".", ".", ".", "."],
            ]
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 0
          width  = 12
          height = 6
          properties = {
            title  = "Retrieve latency"
            region = var.aws_region
            view   = "timeSeries"
            period = 300
            metrics = [
              ["AWS/Bedrock", "InvocationLatency", "Operation", "Retrieve",
                "KnowledgeBaseId", var.knowledge_base_id, { stat = "p50", label = "p50" }],
              ["...", { stat = "p90", label = "p90" }],
              ["...", { stat = "p99", label = "p99" }],
            ]
          }
        },
      ],

      # ----- Row 2: ingestion -----
      [
        {
          type   = "metric"
          x      = 0
          y      = 6
          width  = 12
          height = 6
          properties = {
            title  = "Documents ingested"
            region = var.aws_region
            view   = "timeSeries"
            stat   = "Sum"
            period = 300
            metrics = [
              ["AWS/Bedrock", "DocumentsIngested",
                "KnowledgeBaseId", var.knowledge_base_id,
                "DataSourceId",    var.data_source_id],
              [".",            "DocumentsFailedToIngest", ".", ".", ".", "."],
            ]
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 6
          width  = 12
          height = 6
          properties = {
            title  = "OpenSearch Serverless OCU usage"
            region = var.aws_region
            view   = "timeSeries"
            stat   = "Maximum"
            period = 300
            metrics = [
              ["AWS/AOSS", "SearchOCU", "ClientId", local.account_id,
                "CollectionName", var.opensearch_collection_name],
              [".",        "IndexingOCU", ".", ".", ".", "."],
            ]
          }
        },
      ],

      # ----- Row 3: chunker (only if wired up) -----
      var.chunker_log_group == "" ? [] : [
        {
          type   = "metric"
          x      = 0
          y      = 12
          width  = 8
          height = 6
          properties = {
            title  = "Chunks emitted (custom chunker)"
            region = var.aws_region
            view   = "timeSeries"
            stat   = "Sum"
            period = 300
            metrics = [
              [local.custom_metrics_namespace, "ChunksEmitted"],
            ]
          }
        },
        {
          type   = "metric"
          x      = 8
          y      = 12
          width  = 8
          height = 6
          properties = {
            title  = "Oversized blocks — needs review"
            region = var.aws_region
            view   = "timeSeries"
            stat   = "Sum"
            period = 300
            metrics = [
              [local.custom_metrics_namespace, "OversizedBlocks"],
            ]
          }
        },
        {
          type   = "metric"
          x      = 16
          y      = 12
          width  = 8
          height = 6
          properties = {
            title  = "Chunker errors"
            region = var.aws_region
            view   = "timeSeries"
            stat   = "Sum"
            period = 300
            metrics = [
              [local.custom_metrics_namespace, "ChunkerErrors"],
            ]
          }
        },
      ],
    )
  })
}

resource "aws_cloudwatch_dashboard" "kb" {
  dashboard_name = "${local.name_prefix}-kb"
  dashboard_body = local.dashboard_body
}
