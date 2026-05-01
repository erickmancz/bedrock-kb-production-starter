variable "aws_region" {
  description = "AWS region. Must match the region of the Knowledge Base it will serve."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project identifier used as prefix for resource names."
  type        = string
  default     = "kb-fieldnotes"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,24}$", var.project_name))
    error_message = "project_name must be 3-25 chars, lowercase alphanumeric with hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment name: dev, stg, or prd."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stg", "prd"], var.environment)
    error_message = "environment must be one of: dev, stg, prd."
  }
}

variable "intermediate_bucket_arn" {
  description = "ARN of the S3 bucket Bedrock uses as the intermediate location for custom chunking. Bedrock writes parsed content here and reads chunked output from here. Pass the source bucket ARN from terraform-baseline if you want to colocate, or provision a dedicated bucket."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key encrypting the intermediate bucket. Pass the key ARN from terraform-baseline."
  type        = string
}

variable "memory_size" {
  description = "Lambda memory in MB. Chunking is mostly string manipulation — 1024 MB is plenty. Bump for very large documents."
  type        = number
  default     = 1024
}

variable "timeout_seconds" {
  description = "Lambda timeout. Custom chunking has a hard ceiling of 15 minutes (Lambda max). Most documents finish in under a minute."
  type        = number
  default     = 300
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the chunker."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
