#!/usr/bin/env python3
"""Repair overlapping loop endpoints in custom suburb Metrostroi track data.

In this map both long paths overlap their starting location at the end.
Metrostroi.Load ignores the current path when discovering path joins; it does
not connect a loop path back to itself. Split the last 60 Source units off
each existing path into a small connector path, without renumbering paths 1
and 2. Only run on the unmodified original two-path definition.

The resulting paths (1,2,3,4) have geometrically continuous endpoints and
can be joined by Metrostroi's regular network loader. This is an experiment
until confirmed on the running map: inspect mex_ars_map_check after loading.
"""
import argparse
import json
import math
import re
from pathlib import Path

numbers = re.compile(r"[-+]?\d+(?:\.\d+)?")
def coordinates(raw):
    coords = list(map(float, numbers.findall(raw)))
    if len(coords) != 3:
        raise ValueError("Invalid Vector: " + repr(raw))
    return coords

def vector(coords):
    return "[" + " ".join(f"{v:.6f}".rstrip("0").rstrip(".") for v in coords) + "]"

def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("input", type=Path)
    cli.add_argument("output", type=Path)
    args = cli.parse_args()
    if args.input.resolve() == args.output.resolve():
        cli.error("Use different paths; do not overwrite the original.")
    paths = json.loads(args.input.read_text(encoding="utf-8"))
    if not isinstance(paths, list) or len(paths) != 2:
        cli.error("Expected exactly two paths in the original suburb definition.")
    connectors = []
    for index, path in enumerate(paths, start=1):
        if len(path) < 5:
            cli.error(f"Path {index} too short.")
        first, previous, last = map(coordinates, (path[0], path[-2], path[-1]))
        tangent = [b-a for a,b in zip(previous,last)]
        length = math.dist(previous,last)
        tangent = [v / length for v in tangent]
        # Reject other maps or endpoints that do not overlap along a line.
        projection = sum((last[j] - first[j])*tangent[j] for j in range(3))
        lateral = math.sqrt(max(0,math.dist(first,last)**2 - projection**2))
        if not (100 < projection < 400 and lateral < 12):
            cli.error(f"Path {index} is not the expected overlapping suburb loop "
                      f"(projected={projection:.1f}, lateral={lateral:.1f}).")
        new_end = [first[j] - 60*tangent[j] for j in range(3)]
        if sum((new_end[j] - previous[j])*tangent[j] for j in range(3)) < 20:
            cli.error(f"Insufficient last segment in path {index}.")
        path[-1] = vector(new_end)
        connectors.append([vector(new_end),path[0]])
        print(f"Path {index}: removed {projection:.1f}-unit loop overlap; "
              f"added a 60-unit connector.")
    paths.extend(connectors)
    args.output.write_text(json.dumps(paths,indent=2,ensure_ascii=False) + "\n",encoding="utf-8")
    print("Wrote",args.output,"with four paths; original path IDs 1 and 2 preserved.")

if __name__ == "__main__":
    main()
