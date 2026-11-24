#!/usr/bin/env python3
"""Einfache Workbench-Piktogramme (.info, OS-1.3-Format, 2 Bitebenen) für das Installationspaket: eigene Zeichnung
(Zielflagge), keine Originalgrafik. Aufruf:
  python3 -I tools/mkicon.py project <ausgabe.info> <standardwerkzeug> [TOOLTYPE ...]
  python3 -I tools/mkicon.py tool    <ausgabe.info> [stapel]
  python3 -I tools/mkicon.py drawer  <quelle.info> <ausgabe.info> <links> <oben> <breite> <höhe>
      vorhandenes Schubladen-Piktogramm mit eigenem Fenster (Lage/Größe, nach Piktogrammen, nur Piktogramme)
  python3 -I tools/mkicon.py place   <datei.info> <x> <y>
      feste Lage eines Piktogramms im Fenster seiner Schublade eintragen
  python3 -I tools/mkicon.py retype  <quelle.info> <ausgabe.info> <standardwerkzeug> [TOOLTYPE ...]
      Bild (planar + GlowIcon-FORM) aus einem vorhandenen Piktogramm übernehmen, als Projekt-Piktogramm mit
      Standardwerkzeug und Tooltypes ausgeben (z. B. Werkzeug-Piktogramm als Piktogramm eines Installer-Skripts)
"""
import struct
import sys

W, H = 40, 22


def image():
    # Farben der Workbench: 0 grau, 1 schwarz, 2 weiß, 3 blau. Fahnenstange schwarz, Tuch kariert schwarz/weiß.
    px = [[0] * W for _ in range(H)]
    for y in range(H):
        px[y][4] = px[y][5] = 1
    for y in range(1, 15):
        for x in range(6, 36):
            px[y][x] = 1 if ((x - 6) // 5 + (y - 1) // 5) % 2 else 2
    for x in range(2, 9):
        px[H - 1][x] = 3
    bpr = (W + 15) // 16 * 2
    data = b''
    for plane in range(2):
        for y in range(H):
            row = bytearray(bpr)
            for x in range(W):
                if px[y][x] >> plane & 1:
                    row[x >> 3] |= 0x80 >> (x & 7)
            data += bytes(row)
    return data


def string(s):
    b = s.encode('latin-1') + b'\0'
    return struct.pack('>I', len(b)) + b


def icon(kind, deftool=None, tooltypes=(), stack=0):
    gadget = struct.pack('>IhhhhHHHIIIIIHI', 0, 0, 0, W, H + 1, 0x0004, 0x0003, 0x0001, 1, 0, 0, 0, 0, 0, 0)
    d = struct.pack('>HH', 0xE310, 1) + gadget
    d += struct.pack('>BB', kind, 0)
    d += struct.pack('>IIiiIIi', 1 if deftool else 0, 1 if tooltypes else 0, -0x80000000, -0x80000000, 0, 0, stack)
    assert len(d) == 78
    d += struct.pack('>hhhhhIBBI', 0, 0, W, H, 2, 1, 3, 0, 0) + image()
    if deftool:
        d += string(deftool)
    if tooltypes:
        d += struct.pack('>I', (len(tooltypes) + 1) * 4)
        for t in tooltypes:
            d += string(t)
    return d


def retype(src, deftool, tooltypes):
    b = open(src, 'rb').read()
    assert b[:2] == b'\xe3\x10' and b[0x30] in (3, 4), 'nur Werkzeug-/Projekt-Piktogramme'
    gr, sr = struct.unpack('>II', b[0x16:0x1e])
    dt, tt = struct.unpack('>II', b[0x32:0x3a])
    o = 0x4e
    for ptr in (gr, sr):                         # Image-Strukturen + Bitebenen
        if ptr:
            w, h, depth = struct.unpack('>hhh', b[o + 4:o + 10])
            o += 20 + (w + 15) // 16 * 2 * h * depth
    images = b[0x4e:o]
    if dt:
        o += 4 + struct.unpack('>I', b[o:o + 4])[0]
    if tt:
        n = struct.unpack('>I', b[o:o + 4])[0] // 4 - 1
        o += 4
        for _ in range(n):
            o += 4 + struct.unpack('>I', b[o:o + 4])[0]
    hd = bytearray(b[:0x4e])
    hd[0x30] = 4                                  # WBPROJECT
    hd[0x32:0x3a] = struct.pack('>II', 1, 1 if tooltypes else 0)
    d = bytes(hd) + images + string(deftool)
    if tooltypes:
        d += struct.pack('>I', (len(tooltypes) + 1) * 4)
        for t in tooltypes:
            d += string(t)
    return d + b[o:]                              # Rest: GlowIcon (FORM ICON)


def drawer(src, left, top, width, height):
    # ein vorhandenes Schubladen-Piktogramm (Bild unverändert), mit eigenem Fenster: Lage/Größe, Rollstand 0,
    # DrawerData2 (hinter den Bildern, vor dem GlowIcon): nur Piktogramme, nach Piktogrammen
    b = bytearray(open(src, 'rb').read())
    assert b[:2] == b'\xe3\x10' and b[0x30] == 2 and struct.unpack('>I', b[0x42:0x46])[0], 'kein Schubladen-Piktogramm'
    assert struct.unpack('>I', b[0x2c:0x30])[0] >= 1 and not any(struct.unpack('>III', b[0x32:0x3a] + b[0x46:0x4a]))
    b[0x3a:0x42] = struct.pack('>ii', -0x80000000, -0x80000000)
    b[0x4e:0x56] = struct.pack('>hhhh', left, top, width, height)
    b[0x7e:0x86] = struct.pack('>ii', 0, 0)
    gr, sr = struct.unpack('>II', b[0x16:0x1e])
    o = 0x86
    for ptr in (gr, sr):
        if ptr:
            w, h, depth = struct.unpack('>hhh', b[o + 4:o + 10])
            o += 20 + (w + 15) // 16 * 2 * h * depth
    b[o:o + 6] = struct.pack('>IH', 1, 1)
    return bytes(b)


def place(path, x, y):
    b = bytearray(open(path, 'rb').read())
    assert b[:2] == b'\xe3\x10'
    b[0x3a:0x42] = struct.pack('>ii', x, y)
    return bytes(b)


def main():
    kind, out = sys.argv[1], sys.argv[2]
    if kind == 'retype':
        d = retype(sys.argv[2], sys.argv[4], sys.argv[5:])
        out = sys.argv[3]
    elif kind == 'drawer':
        d = drawer(sys.argv[2], *(int(a) for a in sys.argv[4:8]))
        out = sys.argv[3]
    elif kind == 'place':
        d = place(out, int(sys.argv[3]), int(sys.argv[4]))
    elif kind == 'project':
        d = icon(4, sys.argv[3], sys.argv[4:])
    else:
        d = icon(3, stack=int(sys.argv[3]) if len(sys.argv) > 3 else 16384)
    open(out, 'wb').write(d)


if __name__ == '__main__':
    main()
