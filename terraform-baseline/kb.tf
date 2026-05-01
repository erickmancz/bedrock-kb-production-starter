################################################################################
# Bedrock Knowledge Base + S3 data source.
#
# Two resources:
#   - aws_bedrockagent_knowledge_base: the KB itself, pointing at our
#     OpenSearch Serverless collection and the index we created in
#     opensearch.tf
#   - aws_bedrockagent_data_source: an S3 data source attached to the KB,
#     pulling documents from the source bucket
#
# Chunking strategy is driven by var.chunking_strategy. Default is FIXED_SIZE
# at 300 tokens — matches the AWS console default. The Week 1 article argues
# this is rarely optimal for production; pair this module with
# `custom-chunking-lambda/` (chunking_strategy=NONE) when you need more control.
################################################################################

resource "aws_bedrockagent_knowledge_base" "this" {
  name        = "${local.name_prefix}-kb"
  description = "Knowledge Base for ${local.name_prefix} — Field Notes Week 1 starter"
  role_arn    = aws_iam_role.kb.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:${local.partition}:bedrock:${var.aws_region}::foundation-model/${var.embedding_model_id}"

      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          dimensions = var.embedding_dimensions
        }
      }
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.kb.arn
      vector_index_name = opensearch_index.kb.name
      field_mapping {
        vector_field   = "bedrock-knowledge-base-default-vector"
        text_field     = "AMAZON_BEDROCK_TEXT_CHUNK"
        metadata_field = "AMAZON_BEDROCK_METADATA"
      }
    }
  }

  # KB creation polls the OpenSearch index — make sure it's ready first
  # AND give AOSS time to propagate before Bedrock tries to use it.
  depends_on = [
    time_sleep.wait_for_index_propagation,
    aws_iam_role_policy.kb,
  ]
}

resource "aws_bedrockagent_data_source" "source" {
  name              = "${local.name_prefix}-s3-source"
  description       = "S3 source bucket for ${local.name_prefix} KB"
  knowledge_base_id = aws_bedrockagent_knowledge_base.this.id

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = aws_s3_bucket.source.arn
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = var.chunking_strategy

      dynamic "fixed_size_chunking_configuration" {
        for_each = var.chunking_strategy == "FIXED_SIZE" ? [1] : []
        content {
          max_tokens         = var.fixed_size_max_tokens
          overlap_percentage = var.fixed_size_overlap_percentage
        }
      }
    }
  }
}
