################################################################################
# Provider, data sources, locals.
#
# This module layers observability onto an existing Knowledge Base. It does
# not provision the KB itself — pass the KB ID and related ARNs from the
# terraform-baseline outputs.
################################################################################

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(
    var.tags,
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "bedrock-kb-production-starter/observability"
    }
  )

  # Custom metric namespace — kept distinct from AWS-emitted Bedrock metrics
  # so the dashboard can show both side by side.
  custom_metrics_namespace = "FieldNotes/BedrockKB"
}
