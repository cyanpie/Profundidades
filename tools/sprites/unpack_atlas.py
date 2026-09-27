"""Separa el atlas exportado por comfy_pipeline.js en los PNG individuales del juego.

El atlas llega como índices de paleta (0 = transparente, 1..32 = Endesga 32) comprimidos con deflate,
más un manifiesto [ruta, x, y, tamaño] por sprite. Así el traspaso es pequeño y verificable (checksum).

Uso:  python3 tools/sprites/unpack_atlas.py atlas.json
Salida: assets/sprites/<ruta>.png
"""
import base64
import json
import sys
import zlib
from pathlib import Path

from PIL import Image

ENDESGA32 = [
    "be4a2f", "d77643", "ead4aa", "e4a672", "b86f50", "733e39", "3e2731", "a22633",
    "e43b44", "f77622", "feae34", "fee761", "63c74d", "3e8948", "265c42", "193c3e",
    "124e89", "0099db", "2ce8f5", "ffffff", "c0cbdc", "8b9bb4", "5a6988", "3a4466",
    "262b44", "181425", "ff0044", "68386c", "b55088", "f6757a", "e8b796", "c28569",
]
ROOT = Path(__file__).resolve().parents[2] / "assets" / "sprites"


def checksum(data: bytes) -> int:
    s = 0
    for v in data:
        s = (s * 31 + v) & 0xFFFFFFFF
    return s


def main(path: str) -> None:
    d = json.load(open(path))
    idx = zlib.decompress(base64.b64decode(d["data"]))
    if checksum(idx) != d["checksum"]:
        sys.exit("El atlas llegó corrupto (checksum distinto).")
    w, h = d["W"], d["H"]
    colors = [(0, 0, 0, 0)] + [tuple(int(c[i:i + 2], 16) for i in (0, 2, 4)) + (255,) for c in ENDESGA32]
    atlas = Image.new("RGBA", (w, h))
    atlas.putdata([colors[v] for v in idx])
    for rel, x, y, size in d["manifest"]:
        out = ROOT / f"{rel}.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        atlas.crop((x, y, x + size, y + size)).save(out)
    print(f"{len(d['manifest'])} sprites escritos en {ROOT}")


if __name__ == "__main__":
    main(sys.argv[1])
