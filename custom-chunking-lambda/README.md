# custom-chunking-lambda

Markdown-aware custom chunker for Bedrock Knowledge Bases. Implements the [custom chunking contract](https://docs.aws.amazon.com/bedrock/latest/userguide/kb-chunking-parsing.html) so Bedrock invokes this Lambda during ingestion instead of using its built-in fixed-size or hierarchical strategies.

## Why this exists

The Week 1 article argues that default chunking is the single biggest reason RAG retrieval feels random in production. Fixed-size chunking at 300 tokens splits documents at arbitrary positions — a paragraph explaining a concept ends up cut in half, and neither half has enough anchor for the embedding model to do useful work.

This module is the article's headline recommendation translated into code: a chunker that respects document structure.

## What the chunker actually does

For markdown input (detected by extension or by header patterns):

- **Splits primarily on h1 and h2 boundaries.** Each emitted chunk is anchored to a topic.
- **Keeps fenced code blocks intact.** A half-block is worse than no block.
- **Keeps tables intact.** Column headers travel with the rows that need them.
- **Greedy-packs** atomic blocks up to ~800 tokens (3,200 chars), respecting boundaries above all else.
- **Attaches per-chunk metadata** for filtering at retrieval: `section_path`, `has_code`, `has_table`, `source_file`.

For plain text it falls back to paragraph-aware splitting with a hard token cap.

The `section_path` metadata is the killer feature. At retrieval time you can filter by it:

```python
{"equals": {"key": "has_code", "value": True}}
```

That lets your agent search "only sections with code examples" or "only documents in this folder," dramatically narrowing the search space and improving precision.

## File layout

```
custom-chunking-lambda/
├── lambda/
│   ├── handler.py           The chunker — pure stdlib + boto3
│   └── requirements.txt
└── terraform/
    ├── versions.tf
    ├── main.tf              Provider, locals, archive_file
    ├── variables.tf         Inputs (including ARNs from baseline)
    ├── outputs.tf
    ├── iam.tf               Execution role
    └── lambda.tf            Function + log group + Bedrock invoke permission
```

## How it plugs into the baseline

The chunker is **not** standalone — it runs as part of a Knowledge Base ingestion. To use it:

1. Apply [`terraform-baseline/`](../terraform-baseline) **with `chunking_strategy = "NONE"`**. This tells Bedrock to defer chunking to a custom transformation.
2. Apply this module, passing the source bucket ARN and KMS key ARN from the baseline outputs.
3. Update the data source to point at this Lambda (currently a manual step — see "Wiring the chunker into the data source" below).
4. Trigger an ingestion job. Bedrock will write parsed content to the intermediate bucket, invoke this Lambda for chunking, and ingest the chunks the Lambda returns.

### Wiring the chunker into the data source

The Terraform AWS provider's `aws_bedrockagent_data_source` resource supports a `custom_transformation_configuration` block, but the schema has been moving and the simplest reliable path today is to apply both modules and then patch the data source via CLI:

```bash
KB_ID=$(terraform -chdir=../terraform-baseline output -raw knowledge_base_id)
DS_ID=$(terraform -chdir=../terraform-baseline output -raw data_source_id)
INT_BUCKET=$(terraform -chdir=../terraform-baseline output -raw source_bucket_name)
CHUNKER_ARN=$(terraform output -raw chunker_function_arn)

aws bedrock-agent update-data-source \
  --knowledge-base-id $KB_ID \
  --data-source-id $DS_ID \
  --name "${PROJECT}-${ENV}-s3-source" \
  --data-source-configuration '{
    "type": "S3",
    "s3Configuration": {"bucketArn": "<source-bucket-arn>"}
  }' \
  --vector-ingestion-configuration "{
    \"chunkingConfiguration\": {\"chunkingStrategy\": \"NONE\"},
    \"customTransformationConfiguration\": {
      \"intermediateStorage\": {
        \"s3Location\": {\"uri\": \"s3://$INT_BUCKET/intermediate/\"}
      },
      \"transformations\": [{
        \"stepToApply\": \"POST_CHUNKING\",
        \"transformationFunction\": {
          \"transformationLambdaConfiguration\": {
            \"lambdaArn\": \"$CHUNKER_ARN\"
          }
        }
      }]
    }
  }"
```

Once the AWS provider catches up, this becomes pure Terraform. Track the schema at the [provider docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagent_data_source).

## Run

```bash
cd custom-chunking-lambda/terraform

terraform init
terraform plan \
  -var="intermediate_bucket_arn=$(terraform -chdir=../../terraform-baseline output -raw source_bucket_arn)" \
  -var="kms_key_arn=$(terraform -chdir=../../terraform-baseline output -raw kms_key_arn)"
terraform apply ...
```

## Tuning knobs in `handler.py`

The values that change retrieval quality the most are constants at the top of the handler:

| Constant | Default | Effect of increasing |
|---|---|---|
| `TARGET_CHUNK_TOKENS` | 800 | Larger chunks, more context per chunk, but coarser retrieval |
| `MAX_CHUNK_CHARS` | 6400 | Hard ceiling — beyond this, blocks are emitted standalone with a warning |
| `SPLIT_HEADER_LEVELS` | (1, 2) | Add 3 to split on h3 too — produces many tiny chunks; usually wrong |

Move these to environment variables before tuning in production so changes don't require a redeploy.

## Verifying chunk quality

After re-ingesting with the custom chunker, run [`retrieval-debugger/`](../retrieval-debugger) against the same ten test queries you ran on the default chunker. The chunk-quality report makes the improvement (or lack of it) visible at a glance — section anchors present, code blocks intact, no orphan fragments.

## Cost

The Lambda runs once per ingestion job, billed per invocation duration. For a documentation set of ~1,000 markdown files, expect a single-digit-cents invocation cost. The expensive part of ingestion is the embedding model, which is unaffected by chunking strategy.

## References

- [Bedrock Knowledge Bases — Custom transformations](https://docs.aws.amazon.com/bedrock/latest/userguide/kb-chunking-parsing.html)
- [Lambda — Custom chunking input/output contract](https://docs.aws.amazon.com/bedrock/latest/userguide/kb-chunking-parsing.html#kb-custom-transformation-lambda)
- Article: [Bedrock Knowledge Bases in Production — What the Documentation Won't Tell You](https://awstip.com/bedrock-knowledge-bases-looked-perfect-in-my-demo-production-had-other-plans-19a0f129db45)
