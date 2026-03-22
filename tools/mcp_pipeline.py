#!/usr/bin/env python3
"""
tools/mcp_pipeline.py
MCP server exposing the AXIOM-P&C pipeline layer execution tools.

This is a lightweight MCP server that wraps agents/run_pipeline.py
for use via the Model Context Protocol (stdio transport).
"""

import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
AGENTS_DIR = REPO_ROOT / "agents"


def handle_tool(name: str, args: dict) -> dict:
    """Dispatch a tool call and return the result."""
    if name == "run_pipeline":
        lob = args.get("lob")
        file_path = args.get("file_path")
        cmd = [sys.executable, str(AGENTS_DIR / "run_pipeline.py")]
        if lob:
            cmd += ["--lob", lob]
        if file_path:
            cmd += ["--file", file_path]
        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True,
                cwd=str(REPO_ROOT), timeout=600
            )
            return {"output": result.stdout, "error": result.stderr}
        except Exception as exc:  # noqa: BLE001
            return {"error": str(exc)}
    return {"error": f"Unknown tool: {name}"}


TOOLS_LIST = [
    {
        "name": "run_pipeline",
        "description": "Run the full AXIOM-P&C pipeline via the orchestrator agent.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "lob": {"type": "string", "description": "Optional LOB filter"},
                "file_path": {"type": "string", "description": "Optional input file path"}
            }
        }
    }
]


def main() -> None:
    """Minimal stdio MCP server loop."""
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            continue

        method = req.get("method", "")
        req_id = req.get("id")

        if method == "tools/list":
            response = {"jsonrpc": "2.0", "id": req_id, "result": {"tools": TOOLS_LIST}}
        elif method == "tools/call":
            params = req.get("params", {})
            result = handle_tool(params.get("name", ""), params.get("arguments", {}))
            response = {"jsonrpc": "2.0", "id": req_id, "result": {"content": [{"type": "text", "text": json.dumps(result)}]}}
        else:
            response = {"jsonrpc": "2.0", "id": req_id, "error": {"code": -32601, "message": "Method not found"}}

        print(json.dumps(response), flush=True)


if __name__ == "__main__":
    main()
