variable "aws_region" {
  description = "AWS region where the Knowledge Base will be deployed. Bedrock + Knowledge Bases must both be available."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project identifier used as prefix for resource names. Keep lowercase and short — OpenSearch collection names are capped at 32 characters."
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

variable "embedding_model_id" {
  description = "Bedrock embedding model ID. Titan Text Embeddings v2 is the recommended default for English-language workloads."
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "embedding_dimensions" {
  description = "Vector dimensions emitted by the embedding model. Titan v2 supports 256, 512, or 1024. Lower dimensions reduce storage cost at a small accuracy trade-off."
  type        = number
  default     = 1024

  validation {
    condition     = contains([256, 512, 1024], var.embedding_dimensions)
    error_message = "embedding_dimensions must be 256, 512, or 1024 for Titan v2."
  }
}

variable "chunking_strategy" {
  description = "Chunking strategy: FIXED_SIZE, HIERARCHICAL, SEMANTIC, or NONE. Use NONE when paired with the custom-chunking-lambda module."
  type        = string
  default     = "FIXED_SIZE"

  validation {
    condition     = contains(["FIXED_SIZE", "HIERARCHICAL", "SEMANTIC", "NONE"], var.chunking_strategy)
    error_message = "chunking_strategy must be one of: FIXED_SIZE, HIERARCHICAL, SEMANTIC, NONE."
  }
}

variable "fixed_size_max_tokens" {
  description = "Maximum tokens per chunk when chunking_strategy=FIXED_SIZE. Default of 300 matches AWS docs but is rarely optimal — see the article for guidance."
  type        = number
  default     = 300
}

variable "fixed_size_overlap_percentage" {
  description = "Overlap percentage between consecutive chunks. AWS recommends ≥ 20% to preserve context across boundaries."
  type        = number
  default     = 20

  validation {
    condition     = var.fixed_size_overlap_percentage >= 1 && var.fixed_size_overlap_percentage <= 99
    error_message = "fixed_size_overlap_percentage must be between 1 and 99."
  }
}

variable "kms_deletion_window_days" {
  description = "Pending deletion window for the customer-managed KMS key. AWS minimum is 7, maximum is 30."
  type        = number
  default     = 7

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "kms_deletion_window_days must be between 7 and 30."
  }
}

variable "s3_force_destroy" {
  description = "Whether to allow Terraform to destroy the source bucket even if it contains objects. Use true in dev only."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to all resources, merged with module defaults."
  type        = map(string)
  default     = {}
}

variable "additional_data_access_principals" {
  description = "Optional extra IAM role/user ARNs to grant data plane access on the OpenSearch Serverless collection. Use this when the principal running terraform is an assumed role (e.g., SSO, CI/CD) — pass the underlying role ARN here because data.aws_caller_identity returns the STS assumed-role ARN, which AOSS does not always honor as a Principal. Example: arn:aws:iam::123456789012:role/AdminRole"
  type        = list(string)
  default     = []
}
