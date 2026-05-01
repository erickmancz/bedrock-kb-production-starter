"""
Bedrock Knowledge Bases — custom chunking Lambda.

Implements the custom chunking contract documented at:
  https://docs.aws.amazon.com/bedrock/latest/userguide/kb-chunking-parsing.html

Why a custom chunker:
  Default fixed-size chunking at 300 tokens cuts documents at arbitrary
  positions. A paragraph explaining a concept gets split mid-thought, and
  the resulting chunk has no anchor (no header, no leading sentence) for
  the embedding model to "understand" what it's about.

  This chunker preserves three structural properties that matter for
  retrieval quality on documentation-style content:

    1. SECTION BOUNDARIES — splits primarily on markdown headers (#, ##),
       so each chunk is anchored to a clear topic.

    2. CODE BLOCKS STAY INTACT — fenced code blocks (```...```) are never
       split mid-block. A half-block is worse than no block.

    3. TABLES STAY INTACT — markdown tables (| ... |) are kept as one unit
       so column headers travel with the rows that depend on them.

For non-markdown content (plain .txt), it falls back to paragraph-aware
splitting with a hard token cap.

Per-chunk metadata attached for filtering at retrieval time:
    - section_path: the chain of headers leading to this chunk
                    (e.g., "Chunking > Hierarchical chunking")
    - has_code:     true if the chunk contains a fenced code block
    - has_table:    true if the chunk contains a markdown table
    - source_file:  the original S3 key

Bedrock will surface this metadata to the retrieval API, which means
queries can be filtered like:
    {"equals": {"key": "has_code", "value": true}}
"""

from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass, field
from typing import Iterable

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")

# ----------------------------------------------------------------------------
# Tuning knobs.
#
# These are the values that change retrieval quality the most. They're
# constants here for clarity — bump them via Lambda environment variables
# in production deployments without redeploying code.
# ----------------------------------------------------------------------------

# Approximate tokens per chunk. Heuristic: 1 token ≈ 4 characters of English.
# 800 tokens ≈ 3200 characters — enough for a concept with examples,
# but well below the embedding model's 8K input limit.
TARGET_CHUNK_TOKENS = 800
TARGET_CHUNK_CHARS = TARGET_CHUNK_TOKENS * 4

# Hard ceiling. Chunks bigger than this get force-split even if it
# means cutting between paragraphs.
MAX_CHUNK_CHARS = 1600 * 4  # ~1600 tokens

# Header levels that act as natural split points. h1 + h2 only — splitting
# on h3 produces too many tiny chunks for most docs.
SPLIT_HEADER_LEVELS = (1, 2)


# ----------------------------------------------------------------------------
# Chunk model
# ----------------------------------------------------------------------------

@dataclass
class Chunk:
    """A single chunk emitted to Bedrock."""
    text: str
    section_path: str = ""
    has_code: bool = False
    has_table: bool = False
    source_file: str = ""

    def to_bedrock_dict(self) -> dict:
        """
        Serialize to the shape Bedrock's custom chunking contract expects.

        The required fields are `contentBody` and `contentMetadata`.
        Metadata values must be strings, numbers, or booleans — no nested
        dicts or arrays.
        """
        return {
            "contentBody": self.text,
            "contentMetadata": {
                "section_path": self.section_path,
                "has_code": self.has_code,
                "has_table": self.has_table,
                "source_file": self.source_file,
            },
        }


# ----------------------------------------------------------------------------
# Markdown structure detection
# ----------------------------------------------------------------------------

HEADER_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$", re.MULTILINE)
CODE_FENCE_RE = re.compile(r"^```", re.MULTILINE)
TABLE_ROW_RE = re.compile(r"^\s*\|.+\|\s*$", re.MULTILINE)


def is_markdown(text: str, source_key: str) -> bool:
    """Best-effort heuristic. Filename trumps content."""
    if source_key.lower().endswith((".md", ".markdown", ".mdx")):
        return True
    return bool(HEADER_RE.search(text))


# ----------------------------------------------------------------------------
# Markdown chunking
# ----------------------------------------------------------------------------

@dataclass
class _Block:
    """Intermediate representation: a logical block before final assembly."""
    text: str
    section_path: str
    is_code: bool = False
    is_table: bool = False


def _split_into_atomic_blocks(text: str) -> list[_Block]:
    """
    Walk the document line-by-line and emit atomic blocks.

    "Atomic" means: a code fence is one block, a table is one block,
    paragraphs separated by blank lines are individual blocks, and the
    section_path tracks the most recent h1/h2 chain.
    """
    lines = text.splitlines()
    blocks: list[_Block] = []

    current_h1 = ""
    current_h2 = ""
    buffer: list[str] = []
    in_code = False
    in_table = False
    section_path_at_buffer_start = ""

    def flush_buffer(is_code: bool = False, is_table: bool = False):
        nonlocal buffer
        if not buffer:
            return
        joined = "\n".join(buffer).strip()
        if joined:
            blocks.append(_Block(
                text=joined,
                section_path=section_path_at_buffer_start,
                is_code=is_code,
                is_table=is_table,
            ))
        buffer = []

    def current_section_path() -> str:
        if current_h1 and current_h2:
            return f"{current_h1} > {current_h2}"
        return current_h1 or current_h2 or ""

    for line in lines:
        # Code fence toggles — keep the fence lines in the block.
        if CODE_FENCE_RE.match(line):
            if not in_code:
                # Starting a code block: flush whatever's in the buffer.
                flush_buffer()
                section_path_at_buffer_start = current_section_path()
                in_code = True
                buffer.append(line)
            else:
                # Closing the code block.
                buffer.append(line)
                flush_buffer(is_code=True)
                in_code = False
            continue

        if in_code:
            buffer.append(line)
            continue

        # Table row detection — group consecutive table lines.
        if TABLE_ROW_RE.match(line):
            if not in_table:
                flush_buffer()
                section_path_at_buffer_start = current_section_path()
                in_table = True
            buffer.append(line)
            continue

        if in_table and not TABLE_ROW_RE.match(line):
            flush_buffer(is_table=True)
            in_table = False

        # Header detection — possibly a split point.
        header_match = HEADER_RE.match(line)
        if header_match:
            flush_buffer()
            level = len(header_match.group(1))
            title = header_match.group(2).strip()
            if level == 1:
                current_h1 = title
                current_h2 = ""
            elif level == 2:
                current_h2 = title
            section_path_at_buffer_start = current_section_path()
            buffer.append(line)
            continue

        # Blank line = paragraph boundary.
        if not line.strip():
            flush_buffer()
            section_path_at_buffer_start = current_section_path()
            continue

        # Regular content line.
        if not buffer:
            section_path_at_buffer_start = current_section_path()
        buffer.append(line)

    # Final flush.
    flush_buffer(is_code=in_code, is_table=in_table)
    return blocks


def _assemble_chunks(
    blocks: list[_Block],
    source_key: str,
) -> list[Chunk]:
    """
    Greedy pack atomic blocks into chunks under TARGET_CHUNK_CHARS, never
    splitting a code or table block. Atomic blocks larger than
    MAX_CHUNK_CHARS are emitted as standalone over-sized chunks (rare, but
    we surface them rather than silently truncate).
    """
    chunks: list[Chunk] = []
    current_text: list[str] = []
    current_path = ""
    current_has_code = False
    current_has_table = False
    current_size = 0

    def flush():
        nonlocal current_text, current_has_code, current_has_table, current_size
        if not current_text:
            return
        text = "\n\n".join(current_text).strip()
        if text:
            chunks.append(Chunk(
                text=text,
                section_path=current_path,
                has_code=current_has_code,
                has_table=current_has_table,
                source_file=source_key,
            ))
        current_text = []
        current_has_code = False
        current_has_table = False
        current_size = 0

    for block in blocks:
        block_size = len(block.text)

        # Block alone exceeds the hard ceiling — emit it on its own and
        # log a warning. Better than silently dropping content.
        if block_size > MAX_CHUNK_CHARS:
            logger.warning(
                "Block exceeds MAX_CHUNK_CHARS (%d > %d) in %s — emitting as standalone chunk",
                block_size, MAX_CHUNK_CHARS, source_key,
            )
            flush()
            chunks.append(Chunk(
                text=block.text,
                section_path=block.section_path,
                has_code=block.is_code,
                has_table=block.is_table,
                source_file=source_key,
            ))
            continue

        # Section change forces a flush — keeps section_path consistent
        # within a chunk.
        if current_text and block.section_path != current_path:
            flush()

        # Adding this block would exceed the target — flush first.
        if current_text and current_size + block_size > TARGET_CHUNK_CHARS:
            flush()

        if not current_text:
            current_path = block.section_path

        current_text.append(block.text)
        current_size += block_size
        current_has_code = current_has_code or block.is_code
        current_has_table = current_has_table or block.is_table

    flush()
    return chunks


def chunk_markdown(text: str, source_key: str) -> list[Chunk]:
    """Public entry point for markdown content."""
    blocks = _split_into_atomic_blocks(text)
    return _assemble_chunks(blocks, source_key)


# ----------------------------------------------------------------------------
# Plain-text fallback
# ----------------------------------------------------------------------------

PARAGRAPH_RE = re.compile(r"\n\s*\n")


def chunk_plain_text(text: str, source_key: str) -> list[Chunk]:
    """
    Fallback for non-markdown content. Splits on paragraph boundaries and
    greedy-packs into target-sized chunks. No structural awareness.
    """
    paragraphs = [p.strip() for p in PARAGRAPH_RE.split(text) if p.strip()]
    chunks: list[Chunk] = []
    current: list[str] = []
    current_size = 0

    def flush():
        nonlocal current, current_size
        if current:
            chunks.append(Chunk(
                text="\n\n".join(current),
                section_path="",
                source_file=source_key,
            ))
            current = []
            current_size = 0

    for p in paragraphs:
        # Oversized single paragraph: hard-split on sentence boundaries.
        if len(p) > MAX_CHUNK_CHARS:
            flush()
            for piece in _hard_split(p, TARGET_CHUNK_CHARS):
                chunks.append(Chunk(text=piece, source_file=source_key))
            continue

        if current and current_size + len(p) > TARGET_CHUNK_CHARS:
            flush()
        current.append(p)
        current_size += len(p)

    flush()
    return chunks


def _hard_split(text: str, target_chars: int) -> Iterable[str]:
    """Last-resort splitter. Breaks on sentence punctuation when possible."""
    # Greedy: walk forward target_chars at a time, then snap to the next
    # sentence-ending punctuation if there's one within 200 chars.
    pos = 0
    while pos < len(text):
        end = min(pos + target_chars, len(text))
        if end < len(text):
            window = text[end:end + 200]
            sentence_end = re.search(r"[.!?]\s", window)
            if sentence_end:
                end = end + sentence_end.end()
        yield text[pos:end].strip()
        pos = end


# ----------------------------------------------------------------------------
# Lambda handler
# ----------------------------------------------------------------------------

def lambda_handler(event, context):
    """
    Bedrock Knowledge Bases custom chunking handler.

    Input event shape (April 2026):
        {
            "version": "1.0",
            "knowledgeBaseId": "...",
            "dataSourceId": "...",
            "ingestionJobId": "...",
            "bucketName": "...",                  # intermediate S3 bucket
            "priorTask": "CHUNK",
            "inputFiles": [
                {
                    "originalFileLocation": {
                        "type": "S3",
                        "s3_location": {"uri": "s3://.../source.md"}
                    },
                    "fileMetadata": {...},
                    "contentBatches": [
                        {"key": "intermediate/parsed-content-001.json"}
                    ]
                },
                ...
            ]
        }

    For each input file we read the parsed content from the intermediate
    bucket, chunk it, and write the chunks back to a new key in the same
    bucket. We return a manifest pointing Bedrock at our output keys.

    Bedrock then ingests those chunks (embeds, indexes) on its side.
    """
    logger.info(
        "Custom chunking invoked: kb=%s ds=%s job=%s files=%d",
        event.get("knowledgeBaseId"),
        event.get("dataSourceId"),
        event.get("ingestionJobId"),
        len(event.get("inputFiles", [])),
    )

    bucket = event["bucketName"]
    output_files = []

    for input_file in event.get("inputFiles", []):
        original_uri = input_file["originalFileLocation"]["s3_location"]["uri"]
        source_key = original_uri.split("/", 3)[-1]

        processed_batches = []
        for batch in input_file.get("contentBatches", []):
            batch_key = batch["key"]
            chunks = _process_batch(bucket, batch_key, source_key)
            output_key = batch_key.replace(".json", "-chunked.json")

            payload = {"fileContents": [c.to_bedrock_dict() for c in chunks]}
            s3.put_object(
                Bucket=bucket,
                Key=output_key,
                Body=json.dumps(payload).encode("utf-8"),
                ContentType="application/json",
            )
            processed_batches.append({"key": output_key})
            logger.info("Wrote %d chunks to s3://%s/%s", len(chunks), bucket, output_key)

        output_files.append({
            "originalFileLocation": input_file["originalFileLocation"],
            "fileMetadata": input_file.get("fileMetadata", {}),
            "contentBatches": processed_batches,
        })

    return {"outputFiles": output_files}


def _process_batch(bucket: str, batch_key: str, source_key: str) -> list[Chunk]:
    """Read one parsed-content batch from S3 and chunk every contentBody in it."""
    response = s3.get_object(Bucket=bucket, Key=batch_key)
    parsed = json.loads(response["Body"].read())

    all_chunks: list[Chunk] = []
    for entry in parsed.get("fileContents", []):
        body = entry.get("contentBody", "")
        if not body:
            continue
        if is_markdown(body, source_key):
            all_chunks.extend(chunk_markdown(body, source_key))
        else:
            all_chunks.extend(chunk_plain_text(body, source_key))

    return all_chunks
