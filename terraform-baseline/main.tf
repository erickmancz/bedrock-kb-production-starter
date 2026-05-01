################################################################################
# Provider configuration, data sources, and shared locals.
#
# This file deliberately contains NO resources. Each resource group lives in
# its own file (kb.tf, opensearch.tf, s3.tf, iam.tf, kms.tf) for readability
# and to keep diffs focused.
################################################################################

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# OpenSearch Serverless data plane operations (creating the vector index)
# require signing requests against the collection endpoint, not the AWS API.
# We configure a second provider scoped to the collection.
provider "opensearch" {
  url         = aws_opensearchserverless_collection.kb.collection_endpoint
  aws_region  = var.aws_region
  healthcheck = false
  sign_aws_requests = true
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  name_prefix = "${var.project_name}-${var.environment}"

  # Collection name is constrained: 3-32 chars, lowercase, no underscores.
  # Some name_prefix values would violate this, so we sanitize to 28 chars,
  # leaving room for the 4-char suffixes we append in policy names below.
  collection_name = substr(replace(lower(local.name_prefix), "_", "-"), 0, 28)

  common_tags = merge(
    var.tags,
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "bedrock-kb-production-starter/terraform-baseline"
    }
  )
}
