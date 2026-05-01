################################################################################
# Provider, locals, and the archive_file data source that packages the
# Lambda code into a deployment zip.
################################################################################

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  partition   = data.aws_partition.current.partition
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(
    var.tags,
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "bedrock-kb-production-starter/custom-chunking-lambda"
    }
  )
}

# Package handler.py into a zip Terraform can upload directly. For
# anything more complex (multiple .py files, dependencies beyond boto3)
# move to a build step that produces the zip out-of-band — Terraform
# is not a build tool.
data "archive_file" "handler" {
  type        = "zip"
  source_file = "${path.module}/../lambda/handler.py"
  output_path = "${path.module}/build/handler.zip"
}
