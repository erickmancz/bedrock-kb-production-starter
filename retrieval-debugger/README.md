# retrieval-debugger

A small Python tool that points at a Bedrock Knowledge Base, runs a list of test queries through the **`Retrieve` API** (not `RetrieveAndGenerate`), and produces a per-query report of the raw chunks that came back — including quality signals that flag obvious chunking pathologies.

## Why this exists

From Week 1 of Field Notes:

> Take your ten most common user queries, run them against your knowledge base, and inspect the actual chunks that get retrieved — not the final answer, the raw chunks. Use the Retrieve API instead of RetrieveAndGenerate. You will immediately see whether your chunking is helping or hurting.

This module automates that. Run it before you blame the model for bad answers.

## What you get

For each query, the report shows:

- The query and (optional) expected topic
- A latency measurement for the retrieve call
- A quality score in [0.00, 1.00] aggregating four heuristics
- Every retrieved chunk with: rank, similarity score, source URI, metadata, and the chunk text itself

The four heuristic flags surfaced per chunk:

| Flag | Meaning | What to do |
|---|---|---|
| `starts-mid-sentence` | First letter is lowercase | Chunking is cutting through paragraphs |
| `ends-mid-sentence` | Last char isn't punctuation | Same — boundary is in the wrong place |
| `orphan-code-fence` | Odd number of ` ``` ` markers | Code block was split in half |
| `section-anchor` | Chunk starts with a header or has `section_path` metadata | Good — chunker preserved structure |

A query whose top-5 chunks all show `section-anchor` and zero red flags is doing what it should. A query with three orphan code fences and four mid-sentence starts is where you stop tuning your prompt and start fixing your chunker.

## Install

```bash
cd retrieval-debugger
python -m venv .venv
source .venv/bin/activate  # or .venv\Scripts\activate on Windows
pip install -r requirements.txt
```

## Run

Pull the KB ID from the baseline outputs and point at the example queries:

```bash
KB_ID=$(terraform -chdir=../terraform-baseline output -raw knowledge_base_id)

python debugger.py \
  --knowledge-base-id $KB_ID \
  --queries queries.example.yaml \
  --output reports/
```

Two files land in `reports/`:

- `report-YYYYMMDDTHHMMSS.md` — human-readable, share with reviewers
- `report-YYYYMMDDTHHMMSS.json` — machine-readable, diff across runs to track regressions

## Custom queries

Copy `queries.example.yaml` and fill in **your** ten most common queries. Don't invent them — that defeats the purpose. The point is to characterize how the KB answers questions your users actually ask.

Each entry supports:

```yaml
queries:
  - query: How do I rotate API keys?
    expected_topic: Security operations
    metadata_filter:                         # optional
      equals:
        key: section_path
        value: "Security > Key rotation"
```

The `metadata_filter` block is passed straight through to the Retrieve API. Use it to verify that filters narrow results the way you expect — particularly useful with the `custom-chunking-lambda/` module, which attaches `section_path`, `has_code`, and `has_table` metadata to every chunk.

## How to use this tool effectively

The number that matters isn't the absolute quality score — it's the **delta between runs**. Two suggested workflows:

**Before/after a chunking change:**

```bash
# Run #1 with default chunking
python debugger.py --knowledge-base-id $KB_ID --output reports/before/

# Switch to custom chunking, re-ingest, then:
python debugger.py --knowledge-base-id $KB_ID --output reports/after/

diff reports/before/*.json reports/after/*.json
```

If `quality_score` dropped on more than two queries, your new chunker regressed. Read those queries' reports first.

**As a CI check:**

Run the debugger on every infrastructure change that touches the KB. Fail the build if mean `quality_score` drops below your baseline. The JSON output makes this scriptable.

## Cost

The Retrieve API is billed per request, not per token, and is significantly cheaper than RetrieveAndGenerate (which calls a foundation model). At single-digit-cents-per-thousand-queries pricing, you can run the debugger nightly without thinking about it.

## What the debugger doesn't do

This tool isolates **retrieval** quality. It deliberately doesn't call a foundation model, score factual correctness, or judge whether the answer makes sense — those are different problems with different tools.

If retrieval quality is fine here but your generated answers are still bad, the issue is downstream (prompt, model, or the way you're stitching chunks into the prompt), not in chunking or embedding.

## References

- [Bedrock Agent Runtime — `Retrieve` API](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_agent-runtime_Retrieve.html)
- Article: [Bedrock Knowledge Bases in Production — What the Documentation Won't Tell You](https://awstip.com/bedrock-knowledge-bases-looked-perfect-in-my-demo-production-had-other-plans-19a0f129db45)
