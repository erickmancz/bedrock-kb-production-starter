output "chunker_function_arn" {
  description = "ARN of the chunking Lambda. Pass to the Bedrock data source's vector_ingestion_configuration when chunking_strategy=NONE and a custom transformation is configured."
  value       = aws_lambda_function.chunker.arn
}

output "chunker_function_name" {
  description = "Name of the chunking Lambda — useful for tailing logs."
  value       = aws_lambda_function.chunker.function_name
}

output "chunker_log_group" {
  description = "CloudWatch Logs group for the chunker."
  value       = aws_cloudwatch_log_group.chunker.name
}

output "chunker_role_arn" {
  description = "ARN of the chunker execution role."
  value       = aws_iam_role.chunker.arn
}
