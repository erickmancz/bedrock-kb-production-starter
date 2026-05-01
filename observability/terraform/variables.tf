variable "aws_region" {
  description = "AWS region of the KB being observed."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project identifier."
  type        = string
  default     = "kb-fieldnotes"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stg", "prd"], var.environment)
    error_message = "environment must be one of: dev, stg, prd."
  }
}

variable "knowledge_base_id" {
  description = "ID of the Knowledge Base to observe. Output of terraform-baseline."
  type        = string
}

variable "data_source_id" {
  description = "ID of the S3 data source attached to the KB. Output of terraform-baseline."
  type        = string
}

variable "opensearch_collection_name" {
  description = "Name of the OpenSearch Serverless collection backing the KB."
  type        = string
}

variable "chunker_log_group" {
  description = "Optional CloudWatch Logs group of the custom chunking Lambda. Pass when using the custom-chunking-lambda module — drives the chunker-specific metric filters."
  type        = string
  default     = ""
}

variable "alarm_sns_topic_arn" {
  description = "Optional SNS topic ARN to receive alarm notifications. Leave empty to create alarms without a notification target (still visible in the console)."
  type        = string
  default     = ""
}

variable "ingestion_failure_alarm_threshold" {
  description = "Alert if more than this many ingestion documents fail in a 5-minute window."
  type        = number
  default     = 1
}

variable "retrieval_latency_p99_threshold_ms" {
  description = "Alert if p99 retrieve latency exceeds this many milliseconds over 5 minutes."
  type        = number
  default     = 2000
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
