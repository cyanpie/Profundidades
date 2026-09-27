"""Genera las 3 etapas de grieta de los bloques (GDD §10) como capas transparentes de 32×32.

Las grietas no se generan con IA: un patrón procedural es más consistente y sirve para todos los biomas.
Uso:  python3 tools/sprites/make_cracks.py
Salida: assets/sprites/cracks/grieta_1.png … grieta_3.png
"""
import random
from pathlib import Path

from PIL import Image

SIZE = 32
DARK = (0x18, 0x14, 0x25, 255)      # Endesga 32: contorno
SHADE = (0x3e, 0x27, 0x31, 200)     # borde suave de la grieta
OUT = Path(__file__).resolve().parents[2] / "assets" / "sprites" / "cracks"


def walk(img: Image.Image, rng: random.Random, x: int, y: int, steps: int, dx: int, dy: int) -> None:
    """Dibuja una grieta como una caminata aleatoria con dirección preferente."""
    for _ in range(steps):
        if not (0 <= x < SIZE and 0 <= y < SIZE):
            return
        img.putpixel((x, y), DARK)
        # Sombra a un lado para dar profundidad.
        if 0 <= x + 1 < SIZE and img.getpixel((x + 1, y))[3] == 0:
            img.putpixel((x + 1, y), SHADE)
        r = rng.random()
        if r < 0.55:
            x, y = x + dx, y + dy
        elif r < 0.8:
            x += dx
        else:
            y += dy
        if rng.random() < 0.15:
            dx, dy = dy or dx, dx or dy


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    rng = random.Random(7)
    # Cada etapa añade grietas nuevas encima de las anteriores: la progresión es coherente.
    # Todas nacen cerca del centro (donde se golpea) y se abren hacia los bordes.
    plans = [
        [(16, 15, 7, 1, 1), (15, 15, 6, -1, -1), (16, 15, 4, 1, -1)],
        [(20, 19, 9, 1, 1), (12, 11, 8, -1, -1), (19, 12, 8, 1, -1), (13, 18, 6, -1, 1)],
        [(24, 25, 8, 1, 1), (7, 6, 7, -1, -1), (25, 7, 7, 1, -1), (9, 22, 8, -1, 1), (16, 15, 9, 0, 1), (16, 15, 8, 1, 0)],
    ]
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    for stage, cracks in enumerate(plans, start=1):
        for x, y, steps, dx, dy in cracks:
            walk(img, rng, x, y, steps, dx, dy)
        img.save(OUT / f"grieta_{stage}.png")
        print("escrito", OUT / f"grieta_{stage}.png")


if __name__ == "__main__":
    main()
