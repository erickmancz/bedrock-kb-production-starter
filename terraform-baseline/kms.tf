################################################################################
# Customer-managed KMS key.
#
# Used to encrypt:
#   - The S3 source bucket (SSE-KMS)
#   - The OpenSearch Serverless collection (encryption policy below)
#
# Why a CMK and not the AWS-managed aws/s3 / aws/aoss keys:
#   - You can rotate, audit, and disable a CMK independently
#   - You can grant cross-account access if the KB is consumed elsewhere
#   - Compliance frameworks (PCI-DSS, HIPAA, SOC2) typically require it
################################################################################

data "aws_iam_policy_document" "kms_key" {
  statement {
    sid     = "EnableRootPermissions"
    effect  = "Allow"
    actions = ["kms:*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }

    resources = ["*"]
  }

  # Bedrock service principal needs to use the key when reading objects
  # from the S3 source bucket during ingestion.
  statement {
    sid    = "AllowBedrockServiceUseOfKey"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_kms_key" "kb" {
  description             = "Customer-managed key for ${local.name_prefix} Knowledge Base resources"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_key.json
}

resource "aws_kms_alias" "kb" {
  name          = "alias/${local.name_prefix}-kb"
  target_key_id = aws_kms_key.kb.key_id
}
