################################################################################
# Chunking Lambda + log group + Bedrock invoke permission.
################################################################################

resource "aws_cloudwatch_log_group" "chunker" {
  name              = "/aws/lambda/${local.name_prefix}-chunker"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "chunker" {
  function_name = "${local.name_prefix}-chunker"
  description   = "Markdown-aware custom chunker for Bedrock Knowledge Bases — Field Notes Week 1"
  role          = aws_iam_role.chunker.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  architectures = ["arm64"] # Graviton — cheaper, faster cold start

  filename         = data.archive_file.handler.output_path
  source_code_hash = data.archive_file.handler.output_base64sha256

  memory_size = var.memory_size
  timeout     = var.timeout_seconds

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.chunker.name
  }

  depends_on = [
    aws_iam_role_policy.chunker,
    aws_cloudwatch_log_group.chunker,
  ]
}

# Resource-based policy: allow the Bedrock service principal in this account
# to invoke the function. SourceAccount + SourceArn=knowledge-base/* prevents
# any cross-account Bedrock service from invoking us.
resource "aws_lambda_permission" "bedrock_invoke" {
  statement_id  = "AllowBedrockInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.chunker.function_name
  principal     = "bedrock.amazonaws.com"

  source_account = local.account_id
  source_arn = "arn:${local.partition}:bedrock:${var.aws_region}:${local.account_id}:knowledge-base/*"
}
