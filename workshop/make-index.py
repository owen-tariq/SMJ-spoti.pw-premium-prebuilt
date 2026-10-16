#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Regenerates index.json from items.json and the files it names (see README.md).

    python3 workshop/make-index.py          # writes workshop/index.json, exits 1 on any problem

items.json holds what a person writes (id, type, name, author, summary, file); this adds sha256 and size from
the file as it is now, so run it AFTER the last edit to any file. The checks mirror the app's: an item that
would be refused on the phone stops the script here.
"""
import hashlib, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
MAX_FILE, MAX_ITEMS = 512 * 1024, 200
EXT = {"look": ".json", "eq": ".json", "correction": ".txt"}
HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")


def fail(msg):
    sys.exit("make-index: " + msg)


def check_name(s, what, dot):
    pat = r"[A-Za-z0-9._-]" if dot else r"[A-Za-z0-9_-]"
    if not isinstance(s, str) or not s or not all(re.fullmatch(pat, c) for c in s):
        fail(f"{what} {s!r} has characters outside letters, digits, '-' and '_'")


def check_file_path(path, ext):
    parts = path.split("/")
    if len(parts) > 2 or any(p == "" or p.startswith(".") for p in parts) or ".." in path or not path.lower().endswith(ext):
        fail(f"file {path!r} must be name{ext} or folder/name{ext}")
    for p in parts:
        check_name(p, "file part", True)


def check_look(d, name):
    allowed = {"intensity", "motion", "glowCount", "colours", "colors"}
    if not isinstance(d, dict) or set(d) - allowed:
        fail(f"{name}: look must be an object with only {sorted(allowed)}")
    num = lambda v: isinstance(v, (int, float)) and not isinstance(v, bool)
    if "intensity" in d and not (num(d["intensity"]) and 50 <= d["intensity"] <= 200): fail(f"{name}: intensity 50-200 (percent)")
    if "motion" in d and not (num(d["motion"]) and 25 <= d["motion"] <= 200): fail(f"{name}: motion 25-200 (percent)")
    if "glowCount" in d and d["glowCount"] not in (0, 2, 3, 4): fail(f"{name}: glowCount 0, 2, 3 or 4")
    if "colours" in d and "colors" in d: fail(f"{name}: colours or colors, not both")
    for key in ("colours", "colors"):
        if key in d:
            c = d[key]
            if not isinstance(c, list) or len(c) > 4 or not all(isinstance(x, str) and HEX.match(x) for x in c):
                fail(f"{name}: {key} is up to 4 of \"#RRGGBB\"")


def check_eq(d, name):
    g = d.get("gains") if isinstance(d, dict) and set(d) == {"gains"} else None
    num = lambda v: isinstance(v, (int, float)) and not isinstance(v, bool)
    if not isinstance(g, list) or len(g) != 15 or not all(num(x) and abs(x) <= 12 for x in g):
        fail(f"{name}: eq is {{\"gains\": [15 numbers within ±12]}}")


def check_geq(text, name):
    if not re.match(r"(?i)^GraphicEQ:", text): fail(f"{name}: must start with GraphicEQ:")
    pts = [p.strip() for p in text[10:].strip().split(";") if p.strip()]
    last = 0
    if not 2 <= len(pts) <= 512: fail(f"{name}: 2-512 points")
    for p in pts:
        bits = p.split()
        if len(bits) != 2: fail(f"{name}: bad point {p!r}")
        f, g = float(bits[0]), float(bits[1])
        if not (20 <= f <= 20000 and f > last and abs(g) <= 20): fail(f"{name}: point {p!r} out of range or not rising")
        last = f


def main():
    with open(os.path.join(HERE, "items.json"), encoding="utf-8") as fh:
        items = json.load(fh)
    if not isinstance(items, list) or len(items) > MAX_ITEMS:
        fail("items.json must be a list of at most 200 items")
    out, seen = [], set()
    for it in items:
        if set(it) != {"id", "type", "name", "author", "summary", "file"}:
            fail(f"item {it.get('id')!r}: keys must be id, type, name, author, summary, file")
        check_name(it["id"], "id", False)
        if len(it["id"]) > 64 or it["id"] in seen: fail(f"id {it['id']!r} too long or repeated")
        seen.add(it["id"])
        if it["type"] not in EXT: fail(f"{it['id']}: type must be look, eq or correction")
        for k in ("name", "author", "summary"):
            if not isinstance(it[k], str) or not it[k].strip(): fail(f"{it['id']}: {k} is empty")
        check_file_path(it["file"], EXT[it["type"]])
        with open(os.path.join(HERE, it["file"]), "rb") as fh:
            data = fh.read()
        if not 0 < len(data) <= MAX_FILE: fail(f"{it['file']}: empty or over 512 KB")
        text = data.decode("utf-8")
        if it["type"] == "look": check_look(json.loads(text), it["id"])
        elif it["type"] == "eq": check_eq(json.loads(text), it["id"])
        else: check_geq(text, it["id"])
        out.append(dict(it, sha256=hashlib.sha256(data).hexdigest(), size=len(data)))
    blob = json.dumps({"version": 1, "items": out}, indent=2, ensure_ascii=False) + "\n"
    if len(blob.encode()) > 256 * 1024: fail("index.json would pass 256 KB")
    with open(os.path.join(HERE, "index.json"), "w", encoding="utf-8") as fh:
        fh.write(blob)
    print(f"index.json: {len(out)} items")


main()
