# observability

CloudWatch dashboard, log metric filters, and alarms for a Bedrock Knowledge Base.

The layer most deployments skip — and the reason most teams find out about retrieval regressions from users instead of from their own monitoring.

## What this module provisions

- A **CloudWatch dashboard** combining AWS-emitted Bedrock metrics, OpenSearch Serverless OCU usage, and (optionally) custom chunker metrics
- **Three log metric filters** over the chunker log group, extracting: chunks emitted per ingestion, oversized blocks needing review, and chunker errors
- **Three alarms** on the signals worth paging on: ingestion failures, retrieve p99 latency, retrieve 5xx errors

## File layout

```
observability/
└── terraform/
    ├── versions.tf
    ├── main.tf            Provider, locals, custom metrics namespace
    ├── variables.tf
    ├── outputs.tf
    ├── log_metrics.tf     Metric filters over chunker log group
    ├── dashboard.tf       Three-row dashboard
    └── alarms.tf          Three alarms
```

## Run

This module is meant to be applied **after** `terraform-baseline/` and (optionally) `custom-chunking-lambda/`. Pull their outputs as inputs:

```bash
cd observability/terraform

KB_ID=$(terraform -chdir=../../terraform-baseline output -raw knowledge_base_id)
DS_ID=$(terraform -chdir=../../terraform-baseline output -raw data_source_id)
COLLECTION=$(basename $(terraform -chdir=../../terraform-baseline output -raw opensearch_collection_arn))
CHUNKER_LG=$(terraform -chdir=../../custom-chunking-lambda/terraform output -raw chunker_log_group 2>/dev/null || echo "")

terraform init
terraform apply \
  -var="knowledge_base_id=$KB_ID" \
  -var="data_source_id=$DS_ID" \
  -var="opensearch_collection_name=$COLLECTION" \
  -var="chunker_log_group=$CHUNKER_LG"
```

If you skip the chunker module, leave `chunker_log_group` empty — the chunker-specific widgets and metric filters self-disable, but the rest of the dashboard still works.

## What the dashboard shows

Three rows, each at a 5-minute granularity (the period Bedrock emits at — finer periods produce misleading flat-line gaps):

**Row 1 — Retrieval health**
- Retrieve invocations, client errors, server errors
- Retrieve latency at p50, p90, p99

**Row 2 — Ingestion and capacity**
- Documents ingested vs. documents failed
- OpenSearch Serverless `SearchOCU` and `IndexingOCU` utilization

**Row 3 — Custom chunker (if wired)**
- Chunks emitted per ingestion run
- Oversized blocks (chunks above `MAX_CHUNK_CHARS` in the chunker)
- Errors logged at `ERROR` level by the chunker

The custom metric namespace is `FieldNotes/BedrockKB`, deliberately separate from the AWS-emitted namespaces so they coexist on the same dashboard without naming collisions.

## Alarms

| Alarm | Default threshold | What it tells you |
|---|---|---|
| `ingestion-failures` | `> 1` doc failed in 5 min | Source documents aren't reaching the index. KB is going stale. |
| `retrieve-latency-p99` | `> 2000 ms` over 10 min | Users are waiting longer than expected. Cold OCU, oversized chunks, or model throttling. |
| `retrieve-server-errors` | `> 0` 5xx in 5 min | Bedrock or OpenSearch is failing. Check service health. |

Tune the thresholds in `variables.tf` — defaults are reasonable starting points, not law.

To route alarms to email/Slack/PagerDuty, set `alarm_sns_topic_arn` to an SNS topic ARN. Without one, alarms still fire and are visible in the console — just not pushed anywhere.

## What this module deliberately doesn't do

- **No log retention changes on AWS-managed log groups.** Bedrock manages its own logging when invocation logging is enabled; configure that via the model invocation logging settings in the Bedrock console.
- **No anomaly detection alarms.** They tend to over-fire on KBs with bursty traffic. Use them only after you have a stable baseline.
- **No composite alarms.** Single alarms keep the on-call signal clear. If you need composites for noise reduction, add them outside this module.

## Cost

Cheap. The dashboard is free. Each metric filter is fractions of a cent. Each alarm is ~$0.10/month at the standard tier. Custom metrics emitted via metric filter are billed at the standard CloudWatch rate (~$0.30 per metric per month) — three custom metrics here, so ~$0.90/month total. Trivial relative to the OpenSearch Serverless floor cost.

## References

- [Amazon Bedrock — CloudWatch metrics](https://docs.aws.amazon.com/bedrock/latest/userguide/monitoring-cw.html)
- [OpenSearch Serverless — CloudWatch metrics](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/serverless-cloudwatch.html)
- Article: [Bedrock Knowledge Bases in Production — What the Documentation Won't Tell You](https://awstip.com/bedrock-knowledge-bases-looked-perfect-in-my-demo-production-had-other-plans-19a0f129db45)
