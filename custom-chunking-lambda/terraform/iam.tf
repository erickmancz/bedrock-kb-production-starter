################################################################################
# Execution role for the chunking Lambda.
#
# Permissions granted:
#   - Read parsed content + write chunked content in the intermediate bucket
#   - Use the KMS key to encrypt/decrypt those objects
#   - Write to its own log group
#
# Permissions explicitly NOT granted:
#   - bedrock:* (the Lambda doesn't call Bedrock, Bedrock calls the Lambda)
#   - Cross-bucket access (each chunker is scoped to its KB's bucket)
################################################################################

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "chunker" {
  name               = "${local.name_prefix}-chunker-execution"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "chunker_inline" {
  statement {
    sid    = "AllowS3IntermediateBucket"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      var.intermediate_bucket_arn,
      "${var.intermediate_bucket_arn}/*",
    ]
  }

  statement {
    sid    = "AllowKmsForIntermediateBucket"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey",
    ]
    resources = [var.kms_key_arn]
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.chunker.arn}:*"]
  }
}

resource "aws_iam_role_policy" "chunker" {
  name   = "${local.name_prefix}-chunker-policy"
  role   = aws_iam_role.chunker.id
  policy = data.aws_iam_policy_document.chunker_inline.json
}
