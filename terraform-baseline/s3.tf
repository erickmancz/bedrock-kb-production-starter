################################################################################
# S3 source bucket — where Bedrock reads documents from during ingestion.
#
# Production-leaning defaults applied here:
#   - Versioning ON: surviving accidental document overwrites
#   - SSE-KMS with CMK: encryption at rest using our own key
#   - Public access block: defense in depth against misconfiguration
#   - bucket_key_enabled: reduces KMS API costs at high object counts
#
# Not configured here (intentionally — out of scope for a starter):
#   - Replication to a secondary bucket for DR
#   - Object Lock for write-once compliance scenarios
#   - Lifecycle policies (depends on your retention requirements)
################################################################################

# Bucket name suffix avoids global-namespace collisions across regions/accounts.
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
  numeric = true
}

resource "aws_s3_bucket" "source" {
  bucket        = "${local.name_prefix}-kb-source-${random_string.bucket_suffix.result}"
  force_destroy = var.s3_force_destroy
}

resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.kb.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "source" {
  bucket = aws_s3_bucket.source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bedrock service principal must be able to read source objects and decrypt
# them with our CMK during ingestion. We grant via bucket policy in addition
# to the KB execution role so the Bedrock-managed ingestion plane works.
data "aws_iam_policy_document" "source_bucket" {
  statement {
    sid    = "AllowBedrockServiceRead"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.source.arn,
      "${aws_s3_bucket.source.arn}/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "source" {
  bucket = aws_s3_bucket.source.id
  policy = data.aws_iam_policy_document.source_bucket.json
}
