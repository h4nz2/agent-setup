#!/usr/bin/env python3
"""Token profile of an orchestration session and its subagents, read from Claude Code's transcripts.

Usage: cost-report.py [session-id | path/to/<session>.jsonl]
Without an argument it takes the newest session of the current directory's project
(~/.claude/projects/<cwd with every non-alphanumeric character as '-'>/), i.e. the running one.

One line per agent: cost, turns, peak context, cache reads and writes, and the re-caches that
followed an idle gap longer than the cache lives (5 minutes for subagents, 1 hour for the main
session). Cost is in input-token equivalents: cache read 0.1, cache write 1.25 for subagents and
2.0 for the main session (those weights are assumptions; check current pricing). Output tokens
are left out: transcripts can undercount them.
"""
import collections
import datetime
import glob
import json
import os
import re
import sys

READ, WRITE_SUB, WRITE_MAIN = 0.1, 1.25, 2.0
TTL_SUB, TTL_MAIN = 300, 3600


def responses(path):
    """One (time, usage, model) per API response, in order."""
    seen = set()
    for line in open(path, errors="replace"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        m = d.get("message") or {}
        if d.get("type") != "assistant" or not m.get("usage") or m.get("id") in seen:
            continue
        seen.add(m.get("id"))
        t = datetime.datetime.fromisoformat(d["timestamp"].replace("Z", "+00:00"))
        yield t, m["usage"], m.get("model")


def profile(path, ttl, write_weight):
    p = collections.Counter()
    models = collections.Counter()
    prev = None
    for t, u, model in responses(path):
        read = u.get("cache_read_input_tokens") or 0
        write = u.get("cache_creation_input_tokens") or 0
        ctx = read + write + (u.get("input_tokens") or 0)
        p["turns"] += 1
        p["read"] += read
        p["write"] += write
        p["peak"] = max(p["peak"], ctx)
        models[model] += 1
        if prev and (t - prev).total_seconds() > ttl and ctx > 50_000 and write > ctx / 2:
            p["idle_n"] += 1
            p["idle_write"] += write
        prev = t
    p["cost"] = READ * p["read"] + write_weight * p["write"]
    p["idle_cost"] = write_weight * p["idle_write"]
    p["model"] = (models.most_common(1)[0][0] or "?").replace("claude-", "") if models else "?"
    return p


def h(n):
    return f"{n / 1e6:.1f}M" if n >= 1e6 else f"{n / 1e3:.0f}k"


def find_session(arg):
    root = os.path.join(os.environ.get("CLAUDE_CONFIG_DIR", os.path.expanduser("~/.claude")), "projects")
    if arg and arg.endswith(".jsonl"):
        return arg
    project = os.path.join(root, re.sub(r"[^A-Za-z0-9]", "-", os.getcwd()))
    if arg:
        hits = glob.glob(os.path.join(root, "*", arg + "*.jsonl"))
        if not hits:
            sys.exit(f"no session {arg} under {root}")
        return hits[0]
    sessions = glob.glob(os.path.join(project, "*.jsonl"))
    if not sessions:
        sys.exit(f"no sessions in {project}")
    return max(sessions, key=os.path.getmtime)


def main():
    path = find_session(sys.argv[1] if len(sys.argv) > 1 else None)
    main_p = profile(path, TTL_MAIN, WRITE_MAIN)
    agents = []
    for a in glob.glob(os.path.join(path[: -len(".jsonl")], "subagents", "*.jsonl")):
        try:
            desc = json.load(open(a[: -len(".jsonl")] + ".meta.json")).get("description", "")
        except (OSError, ValueError):
            desc = ""
        agents.append((profile(a, TTL_SUB, WRITE_SUB), desc or os.path.basename(a)))
    agents.sort(key=lambda x: -x[0]["cost"])

    sub_cost = sum(p["cost"] for p, _ in agents)
    total = main_p["cost"] + sub_cost or 1
    print(f"Session {os.path.basename(path)[:8]}: total {h(total)} input-token equivalents")
    print(
        f"  orchestrator: {h(main_p['cost'])} ({100 * main_p['cost'] / total:.0f}%), {main_p['turns']} turns, "
        f"peak {h(main_p['peak'])}, {main_p['idle_n']} re-caches after >1 h idle = {h(main_p['idle_cost'])}"
    )
    if not agents:
        return
    idle = sum(p["idle_cost"] for p, _ in agents)
    print(f"  {len(agents)} agents: {h(sub_cost)} ({100 * sub_cost / total:.0f}%), re-caches after >5 min idle = {h(idle)}")
    print(f"\n  {'cost':>6} {'turns':>5} {'peak':>5} {'reads':>6} {'writes':>6} {'idle':>8}  {'model':<12} agent")
    for p, desc in agents:
        print(
            f"  {h(p['cost']):>6} {p['turns']:>5} {h(p['peak']):>5} {h(p['read']):>6} {h(p['write']):>6} "
            f"{p['idle_n']:>2}={h(p['idle_cost']):>5}  {p['model'][:12]:<12} {desc[:60]}"
        )
    flags = []
    big = [d for p, d in agents if p["peak"] > 400_000]
    if big:
        flags.append(f"{len(big)} agent(s) peaked above 400k context: {'; '.join(big)[:200]}")
    if idle > 0.1 * sub_cost:
        flags.append(f"idle re-caches are {100 * idle / sub_cost:.0f}% of agent cost: agents waited > 5 min in one call")
    for f in flags:
        print(f"  ! {f}")


main()
