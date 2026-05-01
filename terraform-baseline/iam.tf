################################################################################
# Knowledge Base execution role.
#
# The role Bedrock assumes when the KB ingests documents and performs
# retrieval. Permissions are scoped to:
#   - The specific embedding model (no wildcard)
#   - The specific S3 source bucket (no wildcard)
#   - The specific OpenSearch Serverless collection (no wildcard)
#   - The specific KMS key
#
# The aws:SourceAccount + aws:SourceArn conditions on the trust policy
# protect against the confused deputy attack — another AWS account can't
# trick our Bedrock service principal into assuming this role on their
# behalf.
################################################################################

data "aws_iam_policy_document" "kb_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    # Note: we cannot pin to the exact KB ARN at trust policy creation time
    # because the KB doesn't exist yet. After first apply you can tighten this
    # by adding an aws:SourceArn condition matching the KB ARN — see the
    # README for the post-bootstrap hardening step.
  }
}

resource "aws_iam_role" "kb" {
  name               = "${local.name_prefix}-kb-execution"
  assume_role_policy = data.aws_iam_policy_document.kb_assume.json
}

data "aws_iam_policy_document" "kb_inline" {
  statement {
    sid    = "AllowEmbeddingModelInvocation"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
    ]
    resources = [
      "arn:${local.partition}:bedrock:${var.aws_region}::foundation-model/${var.embedding_model_id}",
    ]
  }

  statement {
    sid    = "AllowS3SourceRead"
    effect = "Allow"
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
      variable = "aws:ResourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid    = "AllowKmsForSourceBucket"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey",
    ]
    resources = [aws_kms_key.kb.arn]
  }

  statement {
    sid    = "AllowOpenSearchServerlessCollection"
    effect = "Allow"
    actions = [
      "aoss:APIAccessAll",
    ]
    resources = [aws_opensearchserverless_collection.kb.arn]
  }
}

resource "aws_iam_role_policy" "kb" {
  name   = "${local.name_prefix}-kb-execution-policy"
  role   = aws_iam_role.kb.id
  policy = data.aws_iam_policy_document.kb_inline.json
}
