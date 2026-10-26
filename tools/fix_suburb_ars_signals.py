#!/usr/bin/env python3
"""Normalize ARS code profiles for the user's custom suburb metro map.

Metrostroi stores ARSCodes as strings. A one-element JSON array like ["4"]
cannot express block-dependent 0->40 km/h control, unlike string "04".
A string "046" expresses 0->40->60 as successive blocks clear.

This does not disable EPK or write into the Metrostroi addon. Make a backup
of your existing data/metrostroi_data/signs_*.txt before installing.
"""
import argparse
import json
from pathlib import Path


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("input", type=Path, help="existing Metrostroi signals JSON")
    cli.add_argument("output", type=Path, help="where to write corrected JSON")
    cli.add_argument(
        "--oc", action="append", default=[], metavar="SIGNAL_NAME",
        help="explicit signal whose ARS code must be '1' (OC/no frequency); "
             "repeat for each intended OC section. Never inferred automatically."
    )
    cli.add_argument(
        "--stop", action="append", default=[], metavar="SIGNAL_NAME",
        help="explicit signal requiring code '0' (stop); not the same as OC."
    )
    args = cli.parse_args()
    if args.input.resolve() == args.output.resolve():
        cli.error("Input and output must differ. Never overwrite the source directly.")
    data = json.loads(args.input.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not data.get("Version"):
        cli.error("Expected Metrostroi 1.x signs data with Version.")
    entries = [v for v in data.values() if isinstance(v, dict) and v.get("Class") == "gmod_track_signal"]
    names = {v.get("Name") for v in entries}
    stop, oc = set(args.stop), set(args.oc)
    missing = (stop | oc) - names
    if missing:
        cli.error("Unknown signal name(s): " + ", ".join(sorted(missing)))
    if stop & oc:
        cli.error("A signal cannot be both OC and stop.")
    converted, untouched = 0, 0
    for entry in entries:
        for route in entry.get("Routes", []):
            orig = route.get("ARSCodes")
            if entry.get("Name") in stop:
                route["ARSCodes"] = "0"
            elif entry.get("Name") in oc:
                route["ARSCodes"] = "1"
            elif orig == ["4"] or orig == "4":
                route["ARSCodes"] = "04"
            elif orig == ["6"] or orig == "6":
                route["ARSCodes"] = "046"
            elif isinstance(orig, list):
                route["ARSCodes"] = "".join(map(str, orig))
            else:
                untouched += 1
                continue
            converted += 1
    args.output.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Signals: {len(entries)}, converted routes: {converted}, untouched: {untouched}")
    print("OC signals:", ", ".join(sorted(oc)) or "none selected")
    print("STOP signals:", ", ".join(sorted(stop)) or "none selected")
    print("Wrote:", args.output)
    print("Reminder: set server metrostroi_ars_independent 0 for occupancy-based speed profiles.")


if __name__ == "__main__":
    main()
