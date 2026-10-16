#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Checks every file under workshop/ against index.json, and that the checks reject what they should.

    python3 harness/workshop/validate_test.py

The positive half reads the real catalogue. The negative half runs the same checks (written here the way
WorkshopValidate.h writes them; validate_test.c runs the header itself) on deliberately broken inputs.
"""
import hashlib, json, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "workshop"))
MAX_INDEX, MAX_FILE, MAX_ITEMS = 256 * 1024, 512 * 1024, 200
HEX6 = re.compile(r"^#[0-9A-Fa-f]{6}$")
EXT = {"look": ".json", "eq": ".json", "correction": ".txt"}
KEYS = {"id", "type", "name", "author", "summary", "file", "sha256", "size"}
LOOK_KEYS = {"intensity", "motion", "glowCount", "colours", "colors"}
num = lambda v: isinstance(v, (int, float)) and not isinstance(v, bool)

failures = 0
def check(cond, msg):
    global failures
    print(("ok   " if cond else "FAIL ") + msg)
    if not cond: failures += 1

def id_ok(s): return isinstance(s, str) and re.fullmatch(r"[A-Za-z0-9_-]{1,64}", s) is not None
def file_ok(s, ext):
    return (isinstance(s, str) and s.lower().endswith(ext) and ".." not in s and "\\" not in s
            and re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9._-]*(/[A-Za-z0-9_-][A-Za-z0-9._-]*)?", s) is not None
            and len(s) <= 128)
def https_ok(u): return isinstance(u, str) and re.match(r"(?i)^https://[^/?#@\s\\]+([/?][^\s\\#]*)?$", u) is not None
def sha_ok(s): return isinstance(s, str) and re.fullmatch(r"[0-9a-fA-F]{64}", s) is not None
def size_ok(n, cap): return n > 0 and n <= cap
def look_problem(d):
    if not isinstance(d, dict): return "not an object"
    if set(d) - LOOK_KEYS: return "unknown key"
    if "intensity" in d and not (num(d["intensity"]) and 50 <= d["intensity"] <= 200): return "intensity"
    if "motion" in d and not (num(d["motion"]) and 25 <= d["motion"] <= 200): return "motion"
    if "glowCount" in d and (not num(d["glowCount"]) or d["glowCount"] not in (0, 2, 3, 4)): return "glowCount"
    if "colours" in d and "colors" in d: return "both colour keys"
    for k in ("colours", "colors"):
        if k in d and (not isinstance(d[k], list) or len(d[k]) > 4 or not all(isinstance(c, str) and HEX6.match(c) for c in d[k])): return "colours"
    return None
def eq_problem(d):
    g = d.get("gains") if isinstance(d, dict) and set(d) == {"gains"} else None
    return None if isinstance(g, list) and len(g) == 15 and all(num(x) and abs(x) <= 12 for x in g) else "eq"
def geq_problem(t):
    if not re.match(r"(?i)^GraphicEQ:", t): return "prefix"
    pts = [p.split() for p in t[10:].split(";") if p.strip()]
    last = 0
    if not 2 <= len(pts) <= 512: return "count"
    for p in pts:
        if len(p) != 2: return "shape"
        try: f, g = float(p[0]), float(p[1])
        except ValueError: return "number"
        if not (20 <= f <= 20000 and f > last and abs(g) <= 20): return "range"
        last = f
    return None

# ---- the catalogue
raw = open(os.path.join(ROOT, "index.json"), "rb").read()
check(len(raw) <= MAX_INDEX, f"index.json is {len(raw)} bytes (<= 256 KB)")
index = json.loads(raw)
check(set(index) == {"version", "items"} and index["version"] == 1, "index has version 1 and items only")
items = index["items"]
check(0 < len(items) <= MAX_ITEMS, f"{len(items)} items (<= 200)")
ids = [i["id"] for i in items]
check(len(set(ids)) == len(ids), "ids are unique")
listed = set()
for it in items:
    n = it.get("id")
    check(set(it) == KEYS, f"{n}: keys are exactly the schema's")
    check(id_ok(n) and it["type"] in EXT and file_ok(it["file"], EXT[it["type"]]), f"{n}: id, type and file are well formed")
    check(all(isinstance(it[k], str) and it[k].strip() for k in ("name", "author", "summary")), f"{n}: name, author, summary present")
    path = os.path.join(ROOT, it["file"]); listed.add(os.path.normpath(path))
    data = open(path, "rb").read()
    check(size_ok(len(data), MAX_FILE) and len(data) == it["size"], f"{n}: size {len(data)} matches the index and the cap")
    check(sha_ok(it["sha256"]) and hashlib.sha256(data).hexdigest() == it["sha256"], f"{n}: sha256 matches")
    text = data.decode("utf-8")
    prob = look_problem(json.loads(text)) if it["type"] == "look" else eq_problem(json.loads(text)) if it["type"] == "eq" else geq_problem(text)
    check(prob is None, f"{n}: content valid ({prob or it['type']})")
for sub in ("looks", "eq", "corrections"):
    for f in os.listdir(os.path.join(ROOT, sub)):
        check(os.path.normpath(os.path.join(ROOT, sub, f)) in listed, f"{sub}/{f} is in the index")
looks = [json.loads(open(os.path.join(ROOT, i["file"])).read()) for i in items if i["type"] == "look"]
check(len({json.dumps(l, sort_keys=True) for l in looks}) == len(looks) and len({tuple(l["colours"]) for l in looks}) == len(looks), "looks are all distinct")

# ---- the rejections
good = json.loads(open(os.path.join(ROOT, items[0]["file"])).read())
data = open(os.path.join(ROOT, items[0]["file"]), "rb").read()
check(hashlib.sha256(data + b" ").hexdigest() != items[0]["sha256"], "reject: wrong hash")
check(not sha_ok("abc") and not sha_ok("z" * 64), "reject: malformed sha256")
check(not size_ok(MAX_FILE + 1, MAX_FILE) and not size_ok(0, MAX_FILE), "reject: oversize / empty file")
check(not size_ok(MAX_INDEX + 1, MAX_INDEX), "reject: oversize index")
check(len(data) + 1 != items[0]["size"], "reject: wrong size")
for u in ("http://example.com/", "ftp://x/", "https://", "https:///a", "https://u@evil.com/", "//x/", "javascript:1", "https://a b/"):
    check(not https_ok(u), f"reject: address {u!r}")
check(https_ok("https://example.com/workshop/"), "accept: https address")
for bad in ("..", "a/../b", "../x", "a/b", "", "x y", ".hidden", "a\\b"):
    check(not id_ok(bad), f"reject: id {bad!r}")
for bad in ("../x.json", "a/../b.json", "/etc/x.json", "a/b/c.json", ".h.json", "a\\b.json", "looks/x.exe", "looks/x.json.js", "looks//x.json"):
    check(not file_ok(bad, ".json"), f"reject: file {bad!r}")
for bad in ({"colours": ["red"]}, {"colours": ["#12345"]}, {"colours": ["#GGGGGG"]}, {"colours": ["#111111"] * 5}, {"colours": [1]},
            {"shader": "x"}, {"intensity": 1}, {"intensity": 500}, {"motion": 0}, {"glowCount": 1}, {"glowCount": 5},
            {"colours": ["#111111"], "colors": ["#111111"]}, [], "x"):
    check(look_problem(bad) is not None, f"reject: look {bad!r}")
check(look_problem(dict(good, extra=1)) == "unknown key", "reject: unknown key")
check(eq_problem({"gains": [0] * 14}) and eq_problem({"gains": [13] + [0] * 14}) and eq_problem({"gains": [0] * 15, "x": 1}), "reject: bad eq")
check(geq_problem("20 0; 30 1") and geq_problem("GraphicEQ: 20 0") and geq_problem("GraphicEQ: 30 0; 20 0") and geq_problem("GraphicEQ: 20 x; 30 0"), "reject: bad GraphicEQ")

print("PASS" if not failures else f"{failures} FAILED")
sys.exit(1 if failures else 0)
