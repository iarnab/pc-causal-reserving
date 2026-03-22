#!/usr/bin/env python3
"""
agents/run_pipeline.py
AXIOM-P&C — Multi-Agent Pipeline Orchestrator

Implements a sequential agentic loop over the 5-layer causal reserving
pipeline. Enforces strict layer ordering via a sequencing guard and
dispatches tool calls to R wrappers.

Usage:
    python agents/run_pipeline.py [--lob WC] [--dry-run]
    python agents/run_pipeline.py --interactive

Environment:
    ANTHROPIC_API_KEY  — required (set in .Renviron or environment)
"""

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

import anthropic

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).parent.parent
DB_PATH = REPO_ROOT / "data" / "database" / "causal_reserving.db"
R_WRAPPERS = REPO_ROOT / "tools" / "r_wrappers"

MODEL = "claude-opus-4-6"
MAX_TOKENS = 4096

# Layers that must complete in order
PIPELINE_LAYERS = ["data_ingestion", "anomaly_detection", "causal_reasoning", "narrative"]
LAYER_INDEX = {name: i for i, name in enumerate(PIPELINE_LAYERS)}

# ---------------------------------------------------------------------------
# Tool schemas (Anthropic API format)
# ---------------------------------------------------------------------------

TOOLS_SCHEMA = [
    {
        "name": "pipeline_run_layer_1",
        "description": (
            "Ingest CAS Schedule P data into the SQLite database. "
            "Calls R/layer_1_data functions. Returns rows_ingested, lobs, companies."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "file_path": {
                    "type": "string",
                    "description": "Path to the Schedule P CSV or Excel file."
                },
                "lob": {
                    "type": "string",
                    "description": "Optional: restrict to one LOB (WC, OL, PL, CA, PA, MM)."
                }
            },
            "required": ["file_path"]
        }
    },
    {
        "name": "pipeline_run_layer_2",
        "description": (
            "Run anomaly detection on the ingested triangles. "
            "Calls R/layer_2_anomaly functions. Returns flags_written, error_count, warning_count."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "lob": {
                    "type": "string",
                    "description": "Optional: restrict to one LOB."
                },
                "z_threshold": {
                    "type": "number",
                    "description": "Z-score threshold for flagging (default: 3.0)."
                }
            }
        }
    },
    {
        "name": "pipeline_run_layer_3",
        "description": (
            "Build causal DAG and generate Causal Context Documents (CCDs). "
            "Calls R/layer_3_causal functions. Returns ccds_generated, anomalies_traced."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "lob": {
                    "type": "string",
                    "description": "Optional: restrict to one LOB."
                }
            }
        }
    },
    {
        "name": "pipeline_run_layer_4",
        "description": (
            "Generate LLM-powered reserve narratives grounded in CCD context. "
            "Calls R/layer_4_ai functions using Claude API at temperature=0. "
            "Returns narratives_generated, pending_approval."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "lob": {
                    "type": "string",
                    "description": "Optional: restrict to one LOB."
                },
                "max_narratives": {
                    "type": "integer",
                    "description": "Cap on narratives to generate this run (default: 5)."
                }
            }
        }
    },
    {
        "name": "query_db",
        "description": (
            "Run a read-only SQL query against the causal reserving SQLite database. "
            "Use for status checks and counts, not for data modification."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "sql": {
                    "type": "string",
                    "description": "A SELECT query to execute."
                }
            },
            "required": ["sql"]
        }
    }
]

# ---------------------------------------------------------------------------
# Sequencing guard
# ---------------------------------------------------------------------------

class SequencingGuard:
    """Prevents out-of-order tool calls across pipeline layers."""

    def __init__(self) -> None:
        self._completed: list[str] = []

    def check(self, tool_name: str) -> str | None:
        """Return an error message if the layer cannot run yet, else None."""
        layer_map = {
            "pipeline_run_layer_1": "data_ingestion",
            "pipeline_run_layer_2": "anomaly_detection",
            "pipeline_run_layer_3": "causal_reasoning",
            "pipeline_run_layer_4": "narrative",
        }
        if tool_name not in layer_map:
            return None  # non-layer tools (e.g. query_db) are always allowed

        layer = layer_map[tool_name]
        idx = LAYER_INDEX[layer]
        if idx == 0:
            return None  # Layer 1 has no prerequisite

        prereq = PIPELINE_LAYERS[idx - 1]
        if prereq not in self._completed:
            return (
                f"Sequencing violation: '{layer}' requires '{prereq}' to complete first. "
                f"Completed so far: {self._completed}"
            )
        return None

    def mark_complete(self, tool_name: str) -> None:
        layer_map = {
            "pipeline_run_layer_1": "data_ingestion",
            "pipeline_run_layer_2": "anomaly_detection",
            "pipeline_run_layer_3": "causal_reasoning",
            "pipeline_run_layer_4": "narrative",
        }
        if tool_name in layer_map:
            self._completed.append(layer_map[tool_name])


# ---------------------------------------------------------------------------
# R wrapper execution
# ---------------------------------------------------------------------------

def _run_r_script(script_name: str, args: dict[str, Any]) -> dict[str, Any]:
    """
    Execute an R wrapper script in tools/r_wrappers/ and return JSON result.
    R scripts accept arguments as a JSON string on stdin.
    """
    script_path = R_WRAPPERS / script_name
    if not script_path.exists():
        return {"status": "error", "message": f"R wrapper not found: {script_path}"}

    try:
        result = subprocess.run(
            ["Rscript", str(script_path)],
            input=json.dumps(args),
            capture_output=True,
            text=True,
            timeout=300
        )
        if result.returncode != 0:
            return {
                "status": "error",
                "message": result.stderr.strip() or "R script failed with non-zero exit code"
            }
        return json.loads(result.stdout)
    except subprocess.TimeoutExpired:
        return {"status": "error", "message": "R script timed out after 300s"}
    except json.JSONDecodeError as exc:
        return {"status": "error", "message": f"Failed to parse R output as JSON: {exc}"}
    except Exception as exc:  # noqa: BLE001
        return {"status": "error", "message": str(exc)}


def _query_db(sql: str) -> dict[str, Any]:
    """Execute a read-only SQL query via R wrapper."""
    return _run_r_script("query_db.R", {"sql": sql, "db_path": str(DB_PATH)})


# ---------------------------------------------------------------------------
# Tool dispatch
# ---------------------------------------------------------------------------

TOOL_HANDLERS = {
    "pipeline_run_layer_1": lambda args: _run_r_script("layer1_ingest.R", {**args, "db_path": str(DB_PATH)}),
    "pipeline_run_layer_2": lambda args: _run_r_script("layer2_anomaly.R", {**args, "db_path": str(DB_PATH)}),
    "pipeline_run_layer_3": lambda args: _run_r_script("layer3_causal.R", {**args, "db_path": str(DB_PATH)}),
    "pipeline_run_layer_4": lambda args: _run_r_script("layer4_narrative.R", {**args, "db_path": str(DB_PATH)}),
    "query_db": lambda args: _query_db(args["sql"]),
}


def dispatch(tool_name: str, tool_input: dict[str, Any]) -> str:
    """Dispatch a tool call and return the result as a JSON string."""
    handler = TOOL_HANDLERS.get(tool_name)
    if handler is None:
        return json.dumps({"status": "error", "message": f"Unknown tool: {tool_name}"})
    result = handler(tool_input)
    return json.dumps(result)


# ---------------------------------------------------------------------------
# Agentic loop
# ---------------------------------------------------------------------------

def run_agent(user_message: str, dry_run: bool = False) -> str:
    """
    Run a single agentic session with the orchestrator.

    Implements the standard tool-use loop:
      1. Send user message + tool schemas to Claude
      2. Parse tool_use blocks and dispatch
      3. Feed results back as tool_result blocks
      4. Repeat until no more tool calls or pipeline complete
    """
    guard = SequencingGuard()
    client = anthropic.Anthropic()

    system_prompt = (
        Path(__file__).parent / "5-orchestrator" / "CLAUDE.md"
    ).read_text()

    messages: list[dict] = [{"role": "user", "content": user_message}]

    if dry_run:
        print(f"[dry-run] Would send to {MODEL}: {user_message[:100]}...")
        return "[dry-run] Pipeline not executed."

    while True:
        response = client.messages.create(
            model=MODEL,
            max_tokens=MAX_TOKENS,
            temperature=0,
            system=system_prompt,
            tools=TOOLS_SCHEMA,
            messages=messages
        )

        # Collect assistant turn
        messages.append({"role": "assistant", "content": response.content})

        # Check stop condition
        if response.stop_reason == "end_turn":
            # Extract text response
            texts = [b.text for b in response.content if hasattr(b, "text")]
            return "\n".join(texts)

        if response.stop_reason != "tool_use":
            return f"Unexpected stop_reason: {response.stop_reason}"

        # Process tool calls
        tool_results = []
        for block in response.content:
            if block.type != "tool_use":
                continue

            tool_name = block.name
            tool_input = block.input

            # Sequencing check
            seq_error = guard.check(tool_name)
            if seq_error:
                result_str = json.dumps({"status": "error", "message": seq_error})
            else:
                result_str = dispatch(tool_name, tool_input)
                result_data = json.loads(result_str)
                if result_data.get("status") == "success":
                    guard.mark_complete(tool_name)

            tool_results.append({
                "type": "tool_result",
                "tool_use_id": block.id,
                "content": result_str
            })

        messages.append({"role": "user", "content": tool_results})


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="AXIOM-P&C pipeline orchestrator"
    )
    parser.add_argument(
        "--lob", default=None,
        help="Restrict pipeline run to a single LOB (WC, OL, PL, CA, PA, MM)"
    )
    parser.add_argument(
        "--file", default=None,
        help="Path to the Schedule P input file"
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Print what would be sent to Claude without making API calls"
    )
    parser.add_argument(
        "--interactive", action="store_true",
        help="Enter an interactive prompt loop"
    )
    args = parser.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key and not args.dry_run:
        print("ERROR: ANTHROPIC_API_KEY not set. Add to .Renviron or environment.")
        sys.exit(1)

    if args.interactive:
        print("AXIOM-P&C Orchestrator (interactive mode). Type 'exit' to quit.\n")
        while True:
            try:
                msg = input("You: ").strip()
            except (EOFError, KeyboardInterrupt):
                break
            if msg.lower() in ("exit", "quit"):
                break
            if not msg:
                continue
            print("\nOrchestrator:", run_agent(msg, dry_run=args.dry_run), "\n")
        return

    # Default: full pipeline run
    lob_clause = f" for {args.lob}" if args.lob else " for all supported LOBs"
    file_clause = f" from file '{args.file}'" if args.file else " using data-raw/ defaults"
    message = (
        f"Run the full AXIOM-P&C pipeline{lob_clause}{file_clause}. "
        "Ingest data, detect anomalies, build causal DAGs, and generate narratives."
    )

    print(f"Starting pipeline: {message}\n")
    result = run_agent(message, dry_run=args.dry_run)
    print("\n=== Pipeline Result ===")
    print(result)


if __name__ == "__main__":
    main()
