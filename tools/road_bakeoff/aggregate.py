#!/usr/bin/env python3
"""Merge bakeoff_out/<strategy>/<site>.json into one gate table.

    python3 tools/road_bakeoff/aggregate.py
    python3 tools/road_bakeoff/aggregate.py --out bakeoff_out/evolve_report.md

No ranking and no realism score. A gate cell is PASS, FAIL, or missing.
Failures are listed by x,z under the table.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "bakeoff_out"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", default=str(OUT_DIR))
    parser.add_argument("--out", default=str(OUT_DIR / "evolve_report.md"))
    args = parser.parse_args()
    src = Path(args.src)
    rows = []
    for path in sorted(src.glob("*/*.json")):
        if path.name == "evolve_report.md":
            continue
        try:
            doc = json.loads(path.read_text())
        except json.JSONDecodeError:
            continue
        if "gates" not in doc:
            continue
        rows.append(doc)
    gates = []
    seen = set()
    for doc in rows:
        for name in doc.get("gates", {}):
            if name not in seen:
                seen.add(name)
                gates.append(name)
    strategies = []
    for doc in rows:
        sid = doc.get("strategy", {}).get("id")
        name = doc.get("strategy", {}).get("name", str(sid))
        key = (sid, name)
        if key not in strategies:
            strategies.append(key)
    lines = ["# Evolve report", "", "Headless gates only. fps, frame time and draw calls are not measured.", ""]
    if not rows:
        lines.append("No bakeoff_out JSON files yet.")
    else:
        header = "| Gate | " + " | ".join(f"{sid} {name}" for sid, name in strategies) + " |"
        rule = "|---|" + "|".join("---:" for _ in strategies) + "|"
        lines.append(header)
        lines.append(rule)
        # One column per strategy, collapsed across sites: FAIL if any site failed.
        for gate in gates:
            cells = []
            for sid, _name in strategies:
                marks = []
                for doc in rows:
                    if doc.get("strategy", {}).get("id") != sid:
                        continue
                    g = doc.get("gates", {}).get(gate)
                    if not g:
                        marks.append(f"{doc.get('site')} —")
                    else:
                        flag = "PASS" if g.get("pass") else "FAIL"
                        marks.append(f"{doc.get('site')} {flag} ({g.get('value')})")
                cells.append("<br>".join(marks) if marks else "—")
            lines.append("| %s | %s |" % (gate, " | ".join(cells)))
        lines.append("")
        lines.append("## Failures")
        lines.append("")
        for doc in rows:
            fails = doc.get("failures", [])
            lines.append("### strategy %s %s / %s (%d stored)" % (
                doc.get("strategy", {}).get("id"),
                doc.get("strategy", {}).get("name"),
                doc.get("site"),
                len(fails),
            ))
            lines.append("")
            if not fails:
                lines.append("None stored.")
                lines.append("")
                continue
            lines.append("| Gate | x | z | value |")
            lines.append("|---|---:|---:|---:|")
            for item in fails:
                lines.append("| %s | %.1f | %.1f | %s |" % (
                    item.get("gate", ""),
                    float(item.get("x", 0)),
                    float(item.get("z", 0)),
                    item.get("value", ""),
                ))
            lines.append("")
    dest = Path(args.out)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text("\n".join(lines) + "\n")
    print(f"wrote {dest} from {len(rows)} runs")


if __name__ == "__main__":
    main()
