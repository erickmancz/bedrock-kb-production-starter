################################################################################
# Metric filters over the chunker log group.
#
# The custom chunker emits structured JSON logs (Lambda's logging_config
# is set to JSON in the chunking module). We extract three signals:
#
#   1. Chunks emitted per ingestion — capacity planning + sanity check
#   2. Oversized blocks (chunks larger than MAX_CHUNK_CHARS) — early signal
#      that a source document needs structural review
#   3. Ingestion errors — anything logged at ERROR level
#
# All three only exist when var.chunker_log_group is non-empty.
################################################################################

resource "aws_cloudwatch_log_metric_filter" "chunks_emitted" {
  count = var.chunker_log_group != "" ? 1 : 0

  name           = "${local.name_prefix}-chunks-emitted"
  log_group_name = var.chunker_log_group

  # JSON pattern — Lambda's JSON log_format wraps logger.info() output in:
  #   { "timestamp": "...", "level": "INFO", "message": "Wrote 47 chunks to s3://..." }
  # We match the message prefix.
  pattern = "{ $.message = \"Wrote * chunks*\" }"

  metric_transformation {
    name          = "ChunksEmitted"
    namespace     = local.custom_metrics_namespace
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "oversized_blocks" {
  count = var.chunker_log_group != "" ? 1 : 0

  name           = "${local.name_prefix}-oversized-blocks"
  log_group_name = var.chunker_log_group

  # JSON pattern matching the WARNING line emitted in handler.py when a
  # block exceeds MAX_CHUNK_CHARS.
  pattern = "{ $.message = \"Block exceeds MAX_CHUNK_CHARS*\" }"

  metric_transformation {
    name          = "OversizedBlocks"
    namespace     = local.custom_metrics_namespace
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "chunker_errors" {
  count = var.chunker_log_group != "" ? 1 : 0

  name           = "${local.name_prefix}-chunker-errors"
  log_group_name = var.chunker_log_group

  pattern = "{ $.level = \"ERROR\" }"

  metric_transformation {
    name          = "ChunkerErrors"
    namespace     = local.custom_metrics_namespace
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}
