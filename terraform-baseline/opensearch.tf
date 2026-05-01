################################################################################
# OpenSearch Serverless — vector store for the Knowledge Base.
#
# Three policies are required before a collection can be created:
#   1. Encryption policy (mandatory)
#   2. Network policy (controls public/VPC access)
#   3. Data access policy (who can read/write the collection)
#
# Plus the vector index itself, created via the opensearch provider against
# the collection's data plane endpoint.
#
# Cost note: an OpenSearch Serverless collection has a 2-OCU minimum (~$700/mo
# in us-east-1 as of April 2026). It runs whether or not it's queried. Don't
# leave one running between work sessions during development.
################################################################################

# 1. Encryption policy — uses our customer-managed KMS key.
resource "aws_opensearchserverless_security_policy" "encryption" {
  name = "${local.collection_name}-enc"
  type = "encryption"

  policy = jsonencode({
    Rules = [
      {
        Resource = ["collection/${local.collection_name}"]
        ResourceType = "collection"
      }
    ]
    AWSOwnedKey = false
    KmsARN      = aws_kms_key.kb.arn
  })
}

# 2. Network policy — public for the starter; switch to VPC for production.
#
# Why public is acceptable here: the data access policy below restricts
# *which principals* can do anything with the collection. Network access ≠
# authorization. For regulated workloads, also restrict to a VPC endpoint.
resource "aws_opensearchserverless_security_policy" "network" {
  name = "${local.collection_name}-net"
  type = "network"

  policy = jsonencode([
    {
      Description = "Public access for ${local.collection_name}"
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${local.collection_name}"]
        },
        {
          ResourceType = "dashboard"
          Resource     = ["collection/${local.collection_name}"]
        }
      ]
      AllowFromPublic = true
    }
  ])
}

# 3. Data access policy — grants the KB execution role read/write on indices
# and the operator role (whoever runs terraform) the ability to create the
# index in the first place.
resource "aws_opensearchserverless_access_policy" "data" {
  name = "${local.collection_name}-dap"
  type = "data"

  policy = jsonencode([
    {
      Description = "Data access for ${local.collection_name}"
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${local.collection_name}"]
          Permission = [
            "aoss:CreateCollectionItems",
            "aoss:DescribeCollectionItems",
            "aoss:UpdateCollectionItems",
          ]
        },
        {
          ResourceType = "index"
          Resource     = ["index/${local.collection_name}/*"]
          Permission = [
            "aoss:CreateIndex",
            "aoss:DeleteIndex",
            "aoss:DescribeIndex",
            "aoss:ReadDocument",
            "aoss:UpdateIndex",
            "aoss:WriteDocument",
          ]
        }
      ]
      Principal = concat(
        [
          aws_iam_role.kb.arn,
          data.aws_caller_identity.current.arn,
        ],
        var.additional_data_access_principals,
      )
    }
  ])
}

resource "aws_opensearchserverless_collection" "kb" {
  name = local.collection_name
  type = "VECTORSEARCH"

  description = "Vector store for ${local.name_prefix} Knowledge Base"

  # The collection cannot be created until the encryption and network
  # policies exist. Terraform infers most of these dependencies, but we
  # declare them explicitly to avoid surprises during plan reordering.
  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
  ]
}

################################################################################
# Vector index inside the collection.
#
# This must exist before the Bedrock Knowledge Base resource is created —
# Bedrock validates the index schema during KB creation and fails if it's
# missing or misconfigured.
#
# Schema notes:
#   - bedrock-knowledge-base-default-vector: faiss/hnsw vector field,
#     dimensions match the embedding model (1024 for Titan v2 default)
#   - AMAZON_BEDROCK_TEXT_CHUNK: the raw chunk text returned at retrieval
#   - AMAZON_BEDROCK_METADATA: filterable metadata attached at ingest
################################################################################

resource "opensearch_index" "kb" {
  name                           = "bedrock-kb-default-index"
  number_of_shards               = "2"
  number_of_replicas             = "0"
  index_knn                      = true
  index_knn_algo_param_ef_search = "512"

  mappings = jsonencode({
    properties = {
      "bedrock-knowledge-base-default-vector" = {
        type      = "knn_vector"
        dimension = var.embedding_dimensions
        method = {
          name       = "hnsw"
          engine     = "faiss"
          space_type = "l2"
          parameters = {
            ef_construction = 512
            m               = 16
          }
        }
      }
      "AMAZON_BEDROCK_TEXT_CHUNK" = {
        type  = "text"
        index = true
      }
      "AMAZON_BEDROCK_METADATA" = {
        type  = "text"
        index = false
      }
    }
  })

  depends_on = [
    aws_opensearchserverless_collection.kb,
    aws_opensearchserverless_access_policy.data,
  ]
}

# AOSS index creation returns success before the index is fully queryable
# from the Bedrock control plane. Without this delay, the KB creation that
# follows can intermittently fail with "Index not found" — a documented but
# unfixed timing quirk. 60 seconds covers the propagation window in
# practice. If you hit it anyway on first apply, bump to 90 and re-run.
resource "time_sleep" "wait_for_index_propagation" {
  depends_on      = [opensearch_index.kb]
  create_duration = "60s"
}
