# Workshop catalogue

The default catalogue of Mod Settings > Library > Workshop: small DATA files the tweak downloads over HTTPS
and installs into the local Library with one tap. It points at
`https://raw.githubusercontent.com/owen-tariq/SMJ-spoti.pw-premium-prebuilt/crack/workshop/`, i.e. this folder
on the `crack` branch. Users can paste another https base address under *Catalogue address*.

**Licence:** everything in this folder is original and MIT licensed. JSON cannot carry an SPDX header, so this
note stands for the `.json` and `.txt` files; the Python script carries its own.

## Layout

    index.json          what the app reads (generated, never edit by hand)
    items.json          what you write: id, type, name, author, summary, file
    make-index.py       items.json + the files -> index.json (adds sha256 and size)
    looks/ eq/ corrections/

## Adding an item

1. Put the file under `looks/`, `eq/` or `corrections/` (`.json`, `.json`, `.txt`).
2. Add an entry to `items.json`.
3. Run `python3 workshop/make-index.py` (after the LAST edit of any file: a changed byte changes the hash and
   the app refuses the file). It checks what the app checks and exits 1 on a problem.
4. Run `python3 harness/workshop/validate_test.py`.

## Index schema

    {"version":1,"items":[{"id":"calm-dusk","type":"look"|"eq"|"correction","name":"...","author":"...",
      "summary":"...","file":"looks/calm-dusk.json","sha256":"<64 hex>","size":1234}]}

* `id`: 1-64 of letters, digits, `-`, `_`.
* `file`: `name.ext` or `folder/name.ext`; letters, digits, `.`, `-`, `_`; never starting with `.`, never `..`.
  Extension `.json` for looks and eq, `.txt` for corrections.
* `sha256`/`size`: of the file's exact bytes.

## File formats

* **look** (`.json`): an object with only these keys, all optional:
  `intensity` 50-200 and `motion` 25-200 (percent: the visualizer's reader divides by 100, the layer holds
  the result to 0.5-2 and 0.25-2), `glowCount` 0, 2, 3 or 4, `colours` (or `colors`) up to 4 of `"#RRGGBB"`.
  Installed with `SGLibrarySaveLook`, so the visualizer's Look picker lists it under the item's id.
* **eq** (`.json`): `{"gains": [15 numbers, each within ±12 dB]}`, for the 15 band equalizer (25 Hz ... 16 kHz).
* **correction** (`.txt`): one `GraphicEQ: f g; f g; ...` line as AutoEq writes it: 2-512 points, frequency
  20-20000 Hz rising, gain within ±20 dB. Only generic curves belong here; do not publish "measured" curves
  for named headphones you have not measured.

## Safety rules (the app enforces all of them)

* Data only: no shaders, scripts, binaries or fonts. Anything outside the formats above is refused.
* HTTPS only, and a redirect to anything but https is refused. No cookies, no cache, 20 s timeout.
* Caps: index 256 KB, each file 512 KB, 200 items.
* The sha256 AND the size must match the index before anything is installed.
* No URL inside a file is ever followed; files are fetched only by `base + file` from the index.
* eq and correction files are only *stored*; they change the sound only when the user taps Use.
