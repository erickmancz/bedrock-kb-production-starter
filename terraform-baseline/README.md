# terraform-baseline

Production-leaning Terraform for a Bedrock Knowledge Base on **OpenSearch Serverless**, with KMS encryption, least-privilege IAM, versioned and encrypted S3 source bucket, and a vector index pre-configured for Titan Text Embeddings v2.

## What this module provisions

- A customer-managed **KMS key** (alias: `<name>-kb`) used to encrypt both the S3 source bucket and the OpenSearch Serverless collection
- An **S3 source bucket** with versioning, SSE-KMS, public access block, and a bucket policy granting only the `bedrock.amazonaws.com` service principal in your account
- An **OpenSearch Serverless** collection (type: `VECTORSEARCH`) with three policies (encryption, network, data access) and a pre-created vector index matching Titan v2 embedding dimensions
- An **IAM execution role** for Bedrock, scoped to the specific embedding model, source bucket, KMS key, and collection — no wildcards
- A **Bedrock Knowledge Base** referencing the role and collection, plus an **S3 data source** attached to the KB

## File layout

```
terraform-baseline/
├── versions.tf       Provider requirements only
├── main.tf           Provider config, data sources, locals — no resources
├── variables.tf      All inputs
├── outputs.tf        All outputs
├── kms.tf            CMK and alias
├── s3.tf             Source bucket + policies + random suffix
├── opensearch.tf     Collection + 3 policies + vector index
├── iam.tf            Execution role + scoped policy
└── kb.tf             Knowledge Base + S3 data source
```

## Prerequisites

- Terraform 1.7+
- AWS CLI v2 with credentials in a region where Bedrock + Knowledge Bases are available (tested in `us-east-1`)
- Bedrock model access granted for **`amazon.titan-embed-text-v2:0`** — request it in the Bedrock console under "Model access"
- The principal running Terraform must be in the OpenSearch Serverless **data access policy** for the collection (the module includes `data.aws_caller_identity.current.arn` automatically, so no manual action is needed if you `terraform apply` from the same identity that will create the index)

## Run

```bash
cd terraform-baseline
terraform init
terraform plan -var="environment=dev" -var="project_name=kb-fieldnotes"
terraform apply -var="environment=dev" -var="project_name=kb-fieldnotes"
```

Expected order of creation:
1. KMS key + alias
2. S3 bucket + encryption + policies
3. OpenSearch encryption + network + data policies
4. OpenSearch collection
5. Vector index (data plane call)
6. IAM role + policy
7. Bedrock Knowledge Base
8. Bedrock S3 data source

The full apply takes 5–8 minutes — most of that is the OpenSearch Serverless collection coming online.

## Trigger an ingestion

Upload some documents to the source bucket, then start an ingestion job:

```bash
SOURCE_BUCKET=$(terraform output -raw source_bucket_name)
KB_ID=$(terraform output -raw knowledge_base_id)
DS_ID=$(terraform output -raw data_source_id)

aws s3 cp ./sample-docs/ s3://$SOURCE_BUCKET/ --recursive
aws bedrock-agent start-ingestion-job --knowledge-base-id $KB_ID --data-source-id $DS_ID
```

The `ingestion_command` output also prints the exact CLI line for convenience.

## Test retrieval

Once ingestion finishes (poll with `aws bedrock-agent get-ingestion-job`), verify the KB responds:

```bash
aws bedrock-agent-runtime retrieve \
  --knowledge-base-id $KB_ID \
  --retrieval-query '{"text": "your question here"}' \
  --retrieval-configuration '{"vectorSearchConfiguration": {"numberOfResults": 5}}'
```

For systematic chunk inspection across many queries, see the [`retrieval-debugger/`](../retrieval-debugger) module.

## Variables you'll likely change

| Variable | Default | When to override |
|---|---|---|
| `chunking_strategy` | `FIXED_SIZE` | Set to `NONE` when pairing with `custom-chunking-lambda/` |
| `fixed_size_max_tokens` | `300` | Increase for narrative content; the article argues against the default |
| `fixed_size_overlap_percentage` | `20` | AWS recommends ≥ 20%; below this you start losing context across boundaries |
| `embedding_dimensions` | `1024` | Drop to 512 or 256 to reduce vector storage cost (Titan v2 only) |
| `s3_force_destroy` | `false` | Set to `true` in dev so `terraform destroy` doesn't get stuck on objects |
| `additional_data_access_principals` | `[]` | **Set this when running from CI or assumed-role credentials** — see below |

### Assumed-role gotcha (CI, SSO)

The OpenSearch Serverless data access policy uses `data.aws_caller_identity.current.arn` to grant the operator access to create the vector index. When Terraform runs under an **assumed role** (CI/CD pipelines, AWS SSO, cross-account roles), that data source returns an STS ARN like `arn:aws:sts::ACCT:assumed-role/MyRole/session-id`, which AOSS does not always honor as a `Principal` in data access policies.

If your `terraform apply` fails at the `opensearch_index.kb` step with a 403 or "principal not authorized" error, pass the underlying IAM role ARN explicitly:

```bash
terraform apply \
  -var='additional_data_access_principals=["arn:aws:iam::123456789012:role/MyTerraformRole"]'
```

When running locally with long-lived IAM user credentials, the default works fine.

## Hardening steps after first apply

The module gets you 90% of the way. Two production hardenings to do manually after the first apply:

1. **Tighten the trust policy.** Add an `aws:SourceArn` condition to the Bedrock service principal in `iam.tf`, pinning to the exact KB ARN. This is split out because the KB doesn't exist on the first apply — a chicken-and-egg problem the AWS docs gloss over.

2. **Switch network policy to VPC.** The default network policy allows public access to the collection. Authorization is still controlled by the data access policy (which only lists the KB role and your operator identity), but defense-in-depth says: lock the network too. Replace `AllowFromPublic = true` with a `SourceVPCEs` rule pointing at your VPC endpoint.

## Cost reminder

OpenSearch Serverless has a **2-OCU minimum** that runs whether or not the collection is queried. As of April 2026 in `us-east-1`, that's roughly **$700/month** at list price. Always `terraform destroy` after experimentation:

```bash
terraform destroy -var="environment=dev" -var="project_name=kb-fieldnotes"
```

If you set `s3_force_destroy = false` (the default), you'll need to empty the source bucket manually first.

## References

- [Amazon Bedrock Knowledge Bases — Developer Guide](https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base.html)
- [OpenSearch Serverless — Developer Guide](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/serverless.html)
- [Titan Text Embeddings v2 — Model card](https://docs.aws.amazon.com/bedrock/latest/userguide/titan-embedding-models.html)
- Article: [Bedrock Knowledge Bases in Production — What the Documentation Won't Tell You](https://awstip.com/bedrock-knowledge-bases-looked-perfect-in-my-demo-production-had-other-plans-19a0f129db45)
