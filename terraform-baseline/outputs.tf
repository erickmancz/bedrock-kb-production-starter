output "knowledge_base_id" {
  description = "ID of the Bedrock Knowledge Base. Use with the Retrieve API and the retrieval-debugger module."
  value       = aws_bedrockagent_knowledge_base.this.id
}

output "knowledge_base_arn" {
  description = "ARN of the Bedrock Knowledge Base."
  value       = aws_bedrockagent_knowledge_base.this.arn
}

output "data_source_id" {
  description = "ID of the S3 data source attached to the KB. Used to start ingestion jobs."
  value       = aws_bedrockagent_data_source.source.data_source_id
}

output "source_bucket_name" {
  description = "Name of the S3 bucket where Bedrock reads documents from. Upload files here before triggering ingestion."
  value       = aws_s3_bucket.source.bucket
}

output "source_bucket_arn" {
  description = "ARN of the S3 source bucket."
  value       = aws_s3_bucket.source.arn
}

output "opensearch_collection_arn" {
  description = "ARN of the OpenSearch Serverless collection backing the KB."
  value       = aws_opensearchserverless_collection.kb.arn
}

output "opensearch_collection_endpoint" {
  description = "Data plane endpoint of the OpenSearch Serverless collection."
  value       = aws_opensearchserverless_collection.kb.collection_endpoint
}

output "kb_execution_role_arn" {
  description = "ARN of the IAM role assumed by Bedrock during KB operations."
  value       = aws_iam_role.kb.arn
}

output "kms_key_arn" {
  description = "ARN of the customer-managed KMS key encrypting source data and the collection."
  value       = aws_kms_key.kb.arn
}

output "ingestion_command" {
  description = "AWS CLI command to start an ingestion job after uploading documents to the source bucket."
  value = format(
    "aws bedrock-agent start-ingestion-job --knowledge-base-id %s --data-source-id %s --region %s",
    aws_bedrockagent_knowledge_base.this.id,
    aws_bedrockagent_data_source.source.data_source_id,
    var.aws_region,
  )
}
