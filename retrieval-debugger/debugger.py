"""
Retrieval debugger for Bedrock Knowledge Bases.

The Week 1 article makes one specific recommendation:

    "Take your ten most common user queries, run them against your
    knowledge base, and inspect the actual chunks that get retrieved —
    not the final answer, the raw chunks. Use the Retrieve API instead
    of RetrieveAndGenerate. You will immediately see whether your
    chunking is helping or hurting."

This tool automates that. Point it at a YAML file of test queries and a
KB ID, and it produces a per-query report and a summary chunk-quality
score so regressions are visible the moment they happen.

It does NOT call the foundation model. It only calls the Retrieve API.
That keeps the cost ~zero and isolates retrieval quality from generation
quality — two things teams routinely conflate.

Usage:
    python debugger.py \\
      --knowledge-base-id ABCDEFGHIJ \\
      --queries queries.yaml \\
      --output reports/

The YAML format is documented in queries.example.yaml.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import boto3
import yaml

logging.basicConfig(
    format="%(asctime)s %(levelname)s %(message)s",
    level=logging.INFO,
)
log = logging.getLogger(__name__)


# ----------------------------------------------------------------------------
# Data classes
# ----------------------------------------------------------------------------

@dataclass
class RetrievedChunk:
    """One chunk returned by the Retrieve API, plus our quality signals."""
    rank: int
    score: float
    text: str
    source_uri: str
    metadata: dict[str, Any] = field(default_factory=dict)

    # Quality signals computed locally — see _score_chunk_quality.
    starts_mid_sentence: bool = False
    ends_mid_sentence: bool = False
    contains_orphan_code_fence: bool = False
    has_section_anchor: bool = False


@dataclass
class QueryResult:
    """One query and its retrieval response."""
    query: str
    expected_topic: str
    chunks: list[RetrievedChunk]
    latency_ms: float
    quality_score: float = 0.0


# ----------------------------------------------------------------------------
# Quality scoring
#
# Heuristics, not magic. The point isn't to assign an absolute "correct"
# score — it's to surface obvious chunking pathologies so a human can
# decide whether the chunker needs work.
# ----------------------------------------------------------------------------

SENTENCE_END = (".", "!", "?", ":", ";", ")", "}", "]", "`", '"', "'", "”", "’")
SENTENCE_START_LOWER_THRESHOLD = 1


def _score_chunk_quality(chunk: RetrievedChunk) -> RetrievedChunk:
    """Annotate a chunk with quality signals. Mutates and returns."""
    text = chunk.text.strip()
    if not text:
        return chunk

    # Starts mid-sentence: first non-whitespace character is a lowercase
    # letter, suggesting the chunk begins partway through a thought.
    first_char = text[0]
    chunk.starts_mid_sentence = (
        first_char.isalpha() and first_char.islower()
    )

    # Ends mid-sentence: last non-whitespace character isn't a sentence-ending
    # mark.
    last_char = text[-1]
    chunk.ends_mid_sentence = last_char not in SENTENCE_END

    # Orphan code fence: an odd number of ``` markers means a fenced code
    # block started in this chunk and never closed (or vice versa).
    chunk.contains_orphan_code_fence = text.count("```") % 2 == 1

    # Section anchor: chunk begins with a markdown header, OR has
    # section_path metadata. Either is a sign the custom chunker did
    # its job.
    chunk.has_section_anchor = (
        text.lstrip().startswith("#")
        or bool(chunk.metadata.get("section_path"))
    )

    return chunk


def _aggregate_query_quality(chunks: list[RetrievedChunk]) -> float:
    """
    Crude per-query quality score in [0.0, 1.0].

    Weights:
      +0.4 if no chunk has an orphan code fence
      +0.3 if at least 50% of chunks have a section anchor
      +0.2 if no chunk starts mid-sentence
      +0.1 if no chunk ends mid-sentence

    Tune the weights for your content. The point is to have *a* number
    that drops when chunking degrades.
    """
    if not chunks:
        return 0.0

    score = 0.0
    if not any(c.contains_orphan_code_fence for c in chunks):
        score += 0.4
    anchored = sum(1 for c in chunks if c.has_section_anchor)
    if anchored / len(chunks) >= 0.5:
        score += 0.3
    if not any(c.starts_mid_sentence for c in chunks):
        score += 0.2
    if not any(c.ends_mid_sentence for c in chunks):
        score += 0.1
    return round(score, 2)


# ----------------------------------------------------------------------------
# Retrieve API caller
# ----------------------------------------------------------------------------

def retrieve_chunks(
    client,
    knowledge_base_id: str,
    query: str,
    num_results: int,
    metadata_filter: dict | None = None,
) -> tuple[list[RetrievedChunk], float]:
    """
    Call the Bedrock Agent Runtime Retrieve API for one query.

    Returns the chunks and the call latency in milliseconds.
    """
    config: dict[str, Any] = {
        "vectorSearchConfiguration": {"numberOfResults": num_results}
    }
    if metadata_filter:
        config["vectorSearchConfiguration"]["filter"] = metadata_filter

    start = time.perf_counter()
    response = client.retrieve(
        knowledgeBaseId=knowledge_base_id,
        retrievalQuery={"text": query},
        retrievalConfiguration=config,
    )
    latency_ms = (time.perf_counter() - start) * 1000

    chunks: list[RetrievedChunk] = []
    for rank, item in enumerate(response.get("retrievalResults", []), start=1):
        chunks.append(_score_chunk_quality(RetrievedChunk(
            rank=rank,
            score=item.get("score", 0.0),
            text=item.get("content", {}).get("text", ""),
            source_uri=item.get("location", {})
                .get("s3Location", {})
                .get("uri", ""),
            metadata=item.get("metadata", {}),
        )))

    return chunks, latency_ms


# ----------------------------------------------------------------------------
# Report writers
# ----------------------------------------------------------------------------

def write_markdown_report(
    results: list[QueryResult],
    output_path: Path,
    knowledge_base_id: str,
) -> None:
    """Human-readable report for sharing with reviewers."""
    lines: list[str] = []
    lines.append(f"# Retrieval debugger report")
    lines.append("")
    lines.append(f"- **Knowledge Base:** `{knowledge_base_id}`")
    lines.append(f"- **Generated:** {datetime.now(timezone.utc).isoformat()}")
    lines.append(f"- **Queries evaluated:** {len(results)}")
    if results:
        avg_q = sum(r.quality_score for r in results) / len(results)
        avg_l = sum(r.latency_ms for r in results) / len(results)
        lines.append(f"- **Mean quality score:** {avg_q:.2f} / 1.00")
        lines.append(f"- **Mean retrieve latency:** {avg_l:.0f} ms")
    lines.append("")
    lines.append("---")
    lines.append("")

    for r in results:
        lines.append(f"## Query: {r.query}")
        if r.expected_topic:
            lines.append(f"*Expected topic: {r.expected_topic}*")
        lines.append("")
        lines.append(f"- Quality: **{r.quality_score:.2f}**")
        lines.append(f"- Latency: {r.latency_ms:.0f} ms")
        lines.append(f"- Chunks returned: {len(r.chunks)}")
        lines.append("")

        for c in r.chunks:
            lines.append(f"### Rank {c.rank} — score {c.score:.4f}")
            lines.append(f"**Source:** `{c.source_uri or '<unknown>'}`")

            flags = []
            if c.has_section_anchor:
                flags.append("section-anchor")
            if c.starts_mid_sentence:
                flags.append("starts-mid-sentence")
            if c.ends_mid_sentence:
                flags.append("ends-mid-sentence")
            if c.contains_orphan_code_fence:
                flags.append("orphan-code-fence")
            if flags:
                lines.append(f"**Flags:** {', '.join(flags)}")

            if c.metadata:
                lines.append("**Metadata:**")
                for k, v in c.metadata.items():
                    lines.append(f"- `{k}`: {v}")
            lines.append("")
            lines.append("```")
            preview = c.text if len(c.text) <= 800 else c.text[:800] + " […]"
            lines.append(preview)
            lines.append("```")
            lines.append("")
        lines.append("---")
        lines.append("")

    output_path.write_text("\n".join(lines), encoding="utf-8")
    log.info("Markdown report written to %s", output_path)


def write_json_report(results: list[QueryResult], output_path: Path) -> None:
    """Machine-readable report for diffing across runs."""
    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "queries": [
            {
                "query": r.query,
                "expected_topic": r.expected_topic,
                "latency_ms": r.latency_ms,
                "quality_score": r.quality_score,
                "chunks": [asdict(c) for c in r.chunks],
            }
            for r in results
        ],
    }
    output_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    log.info("JSON report written to %s", output_path)


# ----------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------

def load_queries(path: Path) -> list[dict[str, Any]]:
    with path.open(encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    queries = data.get("queries", [])
    if not queries:
        raise ValueError(f"No queries found in {path}")
    return queries


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Inspect raw chunks returned by a Bedrock Knowledge Base."
    )
    p.add_argument("--knowledge-base-id", required=True,
                   help="KB ID (output of terraform-baseline)")
    p.add_argument("--queries", type=Path, default=Path("queries.example.yaml"),
                   help="Path to YAML file with test queries")
    p.add_argument("--output", type=Path, default=Path("reports"),
                   help="Output directory (created if missing)")
    p.add_argument("--region", default="us-east-1",
                   help="AWS region of the KB")
    p.add_argument("--num-results", type=int, default=5,
                   help="numberOfResults passed to the Retrieve API")
    return p.parse_args()


def main() -> int:
    args = parse_args()

    queries = load_queries(args.queries)
    log.info("Loaded %d queries from %s", len(queries), args.queries)

    args.output.mkdir(parents=True, exist_ok=True)

    client = boto3.client("bedrock-agent-runtime", region_name=args.region)

    results: list[QueryResult] = []
    for i, q in enumerate(queries, start=1):
        query_text = q["query"]
        log.info("[%d/%d] %s", i, len(queries), query_text)
        try:
            chunks, latency = retrieve_chunks(
                client,
                args.knowledge_base_id,
                query_text,
                num_results=args.num_results,
                metadata_filter=q.get("metadata_filter"),
            )
        except client.exceptions.ResourceNotFoundException:
            log.error("Knowledge base %s not found", args.knowledge_base_id)
            return 2
        except Exception as exc:
            log.error("Retrieve failed for query %r: %s", query_text, exc)
            continue

        result = QueryResult(
            query=query_text,
            expected_topic=q.get("expected_topic", ""),
            chunks=chunks,
            latency_ms=latency,
        )
        result.quality_score = _aggregate_query_quality(chunks)
        results.append(result)

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
    write_markdown_report(
        results,
        args.output / f"report-{timestamp}.md",
        args.knowledge_base_id,
    )
    write_json_report(
        results,
        args.output / f"report-{timestamp}.json",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
