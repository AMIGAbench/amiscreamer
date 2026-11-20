#!/usr/bin/env python3
"""Katalog für locale.library (IFF FORM CTLG) aus einer Übersetzung erzeugen.
   tools/catgen.py <strings.h> <sprache.ct> <ausgabe.catalog> [sprache]
strings.h: Zeilen S(NAME, nummer, "englisch") (z. B. src/launcher/launcher_strings.h).
sprache.ct: NAME=Text (UTF-8, '#' Kommentar, \\n = Zeilenumbruch); geschrieben wird ISO-8859-1.
Aufbau: FORM CTLG { FVER "$VER: ...", LANG "<sprache>", STRS { je Text: ULONG nummer, ULONG länge (mit NUL),
Text + NUL, auf 4 Byte aufgefüllt } }."""
import os, re, struct, sys


def chunk(tag, data):
    pad = b"\0" if len(data) & 1 else b""
    return tag + struct.pack(">I", len(data)) + data + pad


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    hdr, ct, out = sys.argv[1:4]
    lang = sys.argv[4] if len(sys.argv) > 4 else os.path.splitext(os.path.basename(ct))[0]
    ids = {m.group(1): int(m.group(2))
           for m in re.finditer(r'S\((\w+),\s*(\d+),', open(hdr, encoding="utf-8").read())}
    strs = b""
    seen = set()
    for n, line in enumerate(open(ct, encoding="utf-8"), 1):
        line = line.rstrip("\r\n")
        if not line or line.startswith("#"):
            continue
        name, sep, text = line.partition("=")
        if not sep or name not in ids:
            sys.exit(f"{ct}:{n}: unbekannter Name '{name}'")
        if name in seen:
            sys.exit(f"{ct}:{n}: '{name}' doppelt")
        seen.add(name)
        b = text.replace("\\n", "\n").encode("iso-8859-1") + b"\0"
        strs += struct.pack(">II", ids[name], len(b)) + b + b"\0" * (-len(b) & 3)
    name = os.path.splitext(os.path.basename(out))[0]
    body = b"CTLG" + chunk(b"FVER", f"$VER: {name}.catalog 1.0 (29.10.2026)\0".encode()) \
        + chunk(b"LANG", lang.encode() + b"\0") + chunk(b"STRS", strs)
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with open(out, "wb") as f:
        f.write(b"FORM" + struct.pack(">I", len(body)) + body)
    print(f"{out}: {len(seen)} von {len(ids)} Texten ({lang})")


if __name__ == "__main__":
    main()
