#!/usr/bin/env python3
"""check-token-efficiency.py — Parse ndjson run logs and compute token metrics.

Part of the audit-paperclip plugin for Claude Code.
Called by audit.sh orchestrator when python3 is available.

Environment variables:
    DATA_DIR      — instance data directory (contains run-logs/<company_id>/<agent_id>/)
    COMPANY_ID    — active company ID
    AGENT_FILTER  — if set, only check this agent name
    AUDIT_TMP     — temp dir containing discovery.json

Output format:
    METRICS: agent=... | avg_input=... | avg_output=... | ratio=... | ...
    SEVERITY: [check-id] Description | section=token-efficiency | agent=AgentName
"""

import json
import os
import sys
from pathlib import Path
from datetime import datetime
from typing import Optional

PRICING = {
    # Anthropic models (per 1M tokens)
    "claude-sonnet-4-5": {"input": 3.0, "output": 15.0},
    "claude-haiku-4-5": {"input": 0.80, "output": 4.0},
    "claude-opus-4-6": {"input": 15.0, "output": 75.0},
    "claude-sonnet-4-6": {"input": 3.0, "output": 15.0},
    # OpenAI models
    "gpt-4o": {"input": 2.50, "output": 10.0},
    "gpt-4.1": {"input": 2.0, "output": 8.0},
    "gpt-4.1-mini": {"input": 0.40, "output": 1.60},
}
# Fallback when the exact model string isn't in PRICING
DEFAULT_PRICING = {"input": 3.0, "output": 15.0}


def parse_ndjson_line(line: str) -> Optional[dict]:
    """Parse a single ndjson line, unwrapping the inner 'chunk' event if present.

    Paperclip log files use a double-JSON encoding: each line is an outer envelope
    with a 'chunk' field whose value is another JSON string (the actual SDK event).
    We try to unwrap that inner JSON; if it fails we return the outer object as-is.
    """
    try:
        outer = json.loads(line.strip())
        # Lines have a "chunk" field containing the actual event JSON string
        chunk = outer.get("chunk", "")
        if chunk:
            try:
                return json.loads(chunk)
            except (json.JSONDecodeError, TypeError):
                pass
        return outer
    except json.JSONDecodeError:
        return None


def parse_run_log(log_path: Path) -> dict:
    """Parse a single run log file and extract token/tool/timing metrics.

    Returns a dict with keys:
        input_tokens, output_tokens, cached_input — cumulative totals
        tool_calls — list of "tool_name:serialized_input" strings for dedup detection
        api_retries_429 — count of rate-limit retries
        first_ts, last_ts — ISO timestamps for duration calculation
        has_permission_errors — True if stderr contained permission denial patterns
        last_event_type — type field of the final event (used to detect died-on-rate-limit)
        duration_sec — float seconds between first and last timestamp
    """
    result: dict = {
        "input_tokens": 0, "output_tokens": 0, "cached_input": 0,
        "tool_calls": [], "api_retries_429": 0,
        "first_ts": None, "last_ts": None,
        "has_permission_errors": False, "last_event_type": None,
    }

    with open(log_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            # Parse timestamp from outer wrapper for duration calculation
            try:
                outer = json.loads(line)
                ts = outer.get("ts")
                if ts:
                    if result["first_ts"] is None:
                        result["first_ts"] = ts
                    result["last_ts"] = ts

                # Detect permission errors from stderr stream — these cause agentic-panic
                if outer.get("stream") == "stderr":
                    chunk_text = outer.get("chunk", "")
                    if any(p in chunk_text.lower() for p in ["requires approval", "permission denied", "this command requires"]):
                        result["has_permission_errors"] = True
            except json.JSONDecodeError:
                continue

            event = parse_ndjson_line(line)
            if not event:
                continue

            etype = event.get("type", "")
            result["last_event_type"] = etype

            # Accumulate token counts from turn.completed events
            if etype == "turn.completed":
                usage = event.get("usage", {})
                result["input_tokens"] += usage.get("input_tokens", 0)
                result["output_tokens"] += usage.get("output_tokens", 0)
                result["cached_input"] += usage.get("cached_input_tokens", 0)

            # Count 429 rate-limit retries; too many = agent is hitting API limits
            if etype == "system" and event.get("subtype") == "api_retry":
                if event.get("error_status") == 429:
                    result["api_retries_429"] += 1

            # Collect tool calls as canonical strings for stuck-retry-loop detection
            if etype == "tool_use":
                tool_name = event.get("name", "")
                # sort_keys ensures identical calls produce identical strings regardless of key order
                tool_input = json.dumps(event.get("input", {}), sort_keys=True)
                result["tool_calls"].append(f"{tool_name}:{tool_input}")

    # Compute wall-clock duration between first and last log event
    result["duration_sec"] = 0
    if result["first_ts"] and result["last_ts"]:
        try:
            t1 = datetime.fromisoformat(result["first_ts"].replace("Z", "+00:00"))
            t2 = datetime.fromisoformat(result["last_ts"].replace("Z", "+00:00"))
            result["duration_sec"] = (t2 - t1).total_seconds()
        except (ValueError, TypeError):
            pass

    return result


def get_cost(model: Optional[str], input_tokens: int, output_tokens: int) -> float:
    """Calculate estimated dollar cost based on model pricing per 1M tokens.

    Uses substring matching so partial model strings like "sonnet-4-6" still resolve.
    Falls back to DEFAULT_PRICING (sonnet rates) when no match is found.
    """
    pricing = DEFAULT_PRICING
    for key, p in PRICING.items():
        if key in (model or "").lower():
            pricing = p
            break
    return (input_tokens * pricing["input"] / 1_000_000) + (output_tokens * pricing["output"] / 1_000_000)


def check_stuck_retry_loop(tool_calls: list) -> bool:
    """Return True if there are >=3 consecutive identical tool calls in the list.

    Three identical calls in a row indicates the agent is stuck in a retry loop —
    calling the same tool with the same arguments repeatedly without making progress.
    """
    if len(tool_calls) < 3:
        return False
    for i in range(len(tool_calls) - 2):
        if tool_calls[i] == tool_calls[i + 1] == tool_calls[i + 2]:
            return True
    return False


def main() -> None:
    """Main entry point: load discovery, iterate agents, emit METRICS and findings."""
    data_dir = os.environ.get("DATA_DIR", "")
    company_id = os.environ.get("COMPANY_ID", "")
    agent_filter = os.environ.get("AGENT_FILTER", "")
    audit_tmp = os.environ.get("AUDIT_TMP", "")

    print("### token-efficiency")

    if not audit_tmp:
        print("WARN: [skipped] AUDIT_TMP not set | section=token-efficiency")
        return

    discovery_path = Path(audit_tmp) / "discovery.json"
    if not discovery_path.exists():
        print("WARN: [skipped] discovery.json not found | section=token-efficiency")
        return

    with open(discovery_path) as f:
        discovery = json.load(f)

    agents = discovery.get("agents", [])
    # Accumulate tokens/min across all agents to assess tier risk at the end
    all_agent_tokens_per_min: list = []

    for agent in agents:
        name = agent.get("name", "unknown")
        if agent_filter and agent_filter != name:
            continue

        agent_id = agent.get("id", "")
        model = agent.get("adapterConfig", {}).get("model", "unknown")

        log_dir = Path(data_dir) / "run-logs" / company_id / agent_id
        if not log_dir.exists():
            continue

        # Analyze only the last 5 runs to keep output focused on recent behavior
        log_files = sorted(log_dir.glob("*.ndjson"))[-5:]
        if not log_files:
            continue

        # Parse all runs; skip files that fail to parse rather than aborting
        runs = []
        for lf in log_files:
            try:
                runs.append((lf.name, parse_run_log(lf)))
            except Exception:
                continue

        if not runs:
            continue

        # Compute aggregate metrics across parsed runs
        total_input = sum(r["input_tokens"] for _, r in runs)
        total_output = sum(r["output_tokens"] for _, r in runs)
        total_cached = sum(r["cached_input"] for _, r in runs)
        n = len(runs)

        avg_input = total_input / n
        avg_output = total_output / n
        # output/input ratio measures how much the agent actually produces vs reads
        ratio = total_output / total_input if total_input > 0 else 0

        empty_runs = sum(1 for _, r in runs if len(r["tool_calls"]) == 0)
        empty_rate = empty_runs / n

        avg_duration = sum(r["duration_sec"] for _, r in runs) / n
        # Cache hit rate: what fraction of input tokens were served from the prompt cache
        cache_hit = total_cached / total_input if total_input > 0 else 0

        avg_cost = get_cost(model, avg_input, avg_output)

        # Track for tier risk — only meaningful if we have timing data
        if avg_duration > 0:
            tokens_per_min = (avg_input + avg_output) / (avg_duration / 60)
            all_agent_tokens_per_min.append((name, tokens_per_min))

        # Emit the METRICS line for Claude to display as a summary table
        print(f"METRICS: agent={name} | avg_input={int(avg_input)} | avg_output={int(avg_output)} | ratio={ratio:.2f} | empty_rate={empty_rate:.2f} | avg_duration={int(avg_duration)}s | cache_hit={cache_hit:.2f} | cost_est=${avg_cost:.2f}")

        # --- Threshold checks ---
        if avg_input > 100_000:
            print(f"WARN: [high-input-tokens] {name} avg {int(avg_input)} input tokens/run (>100K) | section=token-efficiency | agent={name}")

        if avg_output < 100 and total_output > 0:
            print(f"WARN: [low-output-tokens] {name} avg {int(avg_output)} output tokens/run (<100 — agent not producing) | section=token-efficiency | agent={name}")

        if ratio < 0.01 and total_input > 0:
            print(f"WARN: [low-output-ratio] {name} output/input ratio={ratio:.3f} (<0.01 — reading a lot, doing little) | section=token-efficiency | agent={name}")

        if empty_rate > 0.5:
            print(f"WARN: [high-empty-rate] {name} {int(empty_rate * 100)}% of runs had no tool calls | section=token-efficiency | agent={name}")

        if avg_duration > 600:
            print(f"WARN: [long-runs] {name} avg run duration {int(avg_duration)}s (>600s) | section=token-efficiency | agent={name}")

        if cache_hit < 0.30 and total_input > 10000:
            print(f"INFO: [low-cache-hit] {name} cache hit rate={cache_hit:.0%} (<30%) | section=token-efficiency | agent={name}")

        # --- Per-run checks ---
        rolling_avg = total_input / n if n > 0 else 0

        for log_name, run in runs:
            run_id = log_name.replace(".ndjson", "")

            # rate-limited: >2 retries in a single run is unusual and costly
            if run["api_retries_429"] > 2:
                print(f"WARN: [rate-limited] {name} had {run['api_retries_429']} rate-limit retries in run {run_id} | section=token-efficiency | agent={name}")

            # token-velocity-spike: single run using 3x more tokens than average signals runaway context
            if rolling_avg > 0 and run["input_tokens"] > 3 * rolling_avg:
                print(f"WARN: [token-velocity-spike] {name} run {run_id}: {run['input_tokens']} tokens > 3x avg ({int(rolling_avg)}) | section=token-efficiency | agent={name}")

            # agentic-panic: large context + no tool calls + permission errors = agent froze
            if run["input_tokens"] > 50000 and len(run["tool_calls"]) == 0 and run["has_permission_errors"]:
                print(f"ERROR: [agentic-panic] {name} run {run_id}: {int(run['input_tokens'] / 1000)}K tokens, 0 tool calls, permission errors in stderr | section=token-efficiency | agent={name}")

            # died-on-rate-limit: last event was api_retry, meaning the run never completed
            if run["last_event_type"] == "system":
                print(f"ERROR: [died-on-rate-limit] {name} run {run_id} ended on api_retry event | section=token-efficiency | agent={name}")

            # stuck-retry-loop: agent calling the same tool repeatedly without progress
            if check_stuck_retry_loop(run["tool_calls"]):
                print(f"WARN: [stuck-retry-loop] {name} run {run_id} has >=3 consecutive identical tool calls | section=token-efficiency | agent={name}")

    # --- rate-limit-tier-risk: combined throughput across all agents ---
    # Anthropic tier limits are per-organisation; multiple concurrent agents share the quota
    if len(all_agent_tokens_per_min) > 1:
        total_tokens_per_min = sum(tpm for _, tpm in all_agent_tokens_per_min)
        if total_tokens_per_min > 80_000:
            print(f"WARN: [rate-limit-tier-risk] Estimated {int(total_tokens_per_min)} tokens/min across {len(all_agent_tokens_per_min)} agents — exceeds Tier 2 (80K/min) | section=token-efficiency")
        elif total_tokens_per_min > 40_000:
            print(f"WARN: [rate-limit-tier-risk] Estimated {int(total_tokens_per_min)} tokens/min across {len(all_agent_tokens_per_min)} agents — exceeds Tier 1 (40K/min) | section=token-efficiency")


if __name__ == "__main__":
    main()
