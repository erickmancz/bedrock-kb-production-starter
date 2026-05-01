# Bedrock KB Production Starter

Companion repository for **Week 1** of [Golden Jacket Field Notes](https://medium.com/@erickmancz): *"Bedrock Knowledge Bases in Production — What the Documentation Won't Tell You."*

**Read the article:** [on Medium](https://awstip.com/bedrock-knowledge-bases-looked-perfect-in-my-demo-production-had-other-plans-19a0f129db45)

---

## What this repository is

A hands-on starter that translates each production recommendation from the Week 1 article into reference code you can read, run, and adapt. Each module isolates one concern, so you can understand the moving parts before composing them into a real workload.

| Module | What it demonstrates |
|--------|----------------------|
| [`terraform-baseline/`](./terraform-baseline) | A production-leaning Bedrock Knowledge Base with **OpenSearch Serverless**, S3 source bucket, KMS encryption, and least-privilege IAM. The baseline you'd start from before customizing. |
| [`custom-chunking-lambda/`](./custom-chunking-lambda) | The article's headline recommendation: a **markdown-aware custom chunker** that respects headers, code blocks, and tables instead of cutting documents at arbitrary token counts. |
| [`retrieval-debugger/`](./retrieval-debugger) | A Python tool that uses the **`Retrieve` API** (not `RetrieveAndGenerate`) to inspect raw chunks for a list of queries. Exports a chunk-quality report. The "try this before changing anything else" tool. |
| [`observability/`](./observability) | CloudWatch dashboard, metric filters, and alarms covering retrieval latency, ingestion failures, and chunk-level signals. The layer most deployments skip. |

## What this repository is NOT

- **Not production-ready.** Each module is a reference implementation focused on clarity, not hardening. WAF, multi-region, fine-grained billing controls, and compliance-specific artifacts (HIPAA, PCI-DSS) are deliberately out of scope.
- **Not a replacement for the AWS documentation.** Every module links back to the official docs. If AWS changes an API, the documentation is authoritative, not this repo.
- **Not a framework.** Don't import from this repo. Read the code, adapt the patterns, write your own.

> **Version note:** Bedrock Knowledge Bases is moving fast. Every module includes a `versions.tf` (Terraform) or `requirements.txt` (Python) with the tested versions. If you encounter API drift, open an issue with your provider/SDK version and the error — I will update.

---

## Two paths to learn the layers

There are two complementary paths through this repository, depending on what you want to understand first.

### Path 1 — Infrastructure-first

Best if you want to see the whole pipeline working end-to-end before optimizing any one piece:

1. `terraform-baseline/` — provision the KB, sync some sample documents, query it from the console
2. `observability/` — layer the dashboard on top so you can see what's happening
3. `retrieval-debugger/` — point it at the KB and inspect actual retrieval behavior
4. `custom-chunking-lambda/` — re-ingest with custom chunking, compare retrieval quality

### Path 2 — Quality-first

Best if you already have a Knowledge Base and want to understand why your retrieval feels random:

1. `retrieval-debugger/` — characterize your current retrieval quality with real queries
2. `custom-chunking-lambda/` — fix the upstream issue (chunking) instead of the downstream symptom (model)
3. `terraform-baseline/` — adopt the IAM and encryption baseline if your current one is permissive
4. `observability/` — instrument so the next regression is visible the moment it happens

---

## Prerequisites

- AWS account with access to **Amazon Bedrock** in a region where Knowledge Bases is available (tested in `us-east-1`)
- Bedrock model access granted for **Titan Text Embeddings v2** (`amazon.titan-embed-text-v2:0`) — request it in the Bedrock console if needed
- AWS CLI v2 configured with credentials that can create Bedrock, OpenSearch Serverless, S3, IAM, KMS, Lambda, and CloudWatch resources
- **Terraform 1.7+** for the infrastructure modules
- **Python 3.11+** for the chunking Lambda and the retrieval debugger

---

## Cost expectations

Knowledge Bases itself has no per-hour fee — you pay for what it sits on top of. The costs that surprise people:

| Component | Order of magnitude (us-east-1, April 2026) | Notes |
|---|---|---|
| OpenSearch Serverless collection | ~$700/month minimum (2 OCUs × 24×30) | Hard floor — runs whether you query it or not |
| Titan Embeddings v2 ingestion | ~$0.02 per 1M tokens | One-time per ingestion job |
| Bedrock model invocations (RetrieveAndGenerate) | Varies by model | Sonnet 4.5 ≫ Haiku 4.5 |
| S3 source bucket | Cents | Negligible |
| KMS CMK | $1/month + per-request | Negligible at moderate traffic |

**Watchout:** OpenSearch Serverless charges by the hour for provisioned OCUs (OpenSearch Compute Units), with a 2-OCU minimum per workload. That floor is the single biggest line item in most KB deployments. Plan accordingly. Some teams move infrequently-queried KBs to S3 Vectors specifically to avoid this floor — see the trade-off discussion in the article.

**Always:** `terraform destroy` after experiments. Forgetting an OpenSearch Serverless collection running for a weekend is a real way to surprise yourself with a four-figure bill.

---

## Architecture overview

The four modules answer four different questions:

| Question | Answer |
|----------|--------|
| Where does my data live, and who can read it? | **`terraform-baseline/`** |
| How do I split my documents so retrieval actually works? | **`custom-chunking-lambda/`** |
| Why is my retrieval quality unpredictable? | **`retrieval-debugger/`** |
| How will I know when something regresses? | **`observability/`** |

For the full reasoning behind each recommendation, read the [Week 1 article](https://awstip.com/bedrock-knowledge-bases-looked-perfect-in-my-demo-production-had-other-plans-19a0f129db45).

---

## License

MIT. See [LICENSE](./LICENSE). Opinions expressed here are my own.

---

## Feedback

If something is broken, outdated, or unclear, open an issue. Pull requests welcome — especially when an AWS provider update breaks a pattern here. This repo evolves with the service.

**Author:** [Erick Mancz](https://linkedin.com/in/erick-mancz) · AWS Golden Jacket · [Medium](https://medium.com/@erickmancz) · [AWS Builder Center](https://builder.aws.com/community/@imancz)
