# Pipeline de sprites

Todo el arte del juego sale de aquí, generado localmente con la GPU (RTX 3060) en ComfyUI y reducido a pixel art de verdad en la paleta **Endesga 32**.

## Modelos (ComfyUI)

| Archivo | Tipo | Origen |
|---|---|---|
| `sd_xl_base_1.0.safetensors` | checkpoint | stabilityai/stable-diffusion-xl-base-1.0 |
| `pixel-art-xl.safetensors` | LoRA | nerijs/pixel-art-xl |

## Archivos

| Archivo | Qué hace |
|---|---|
| `assets.json` | Catálogo: id, categoría, tamaño final, si lleva transparencia, semilla y prompt de cada sprite |
| `comfy_pipeline.js` | Se ejecuta **dentro de la página de ComfyUI** (`http://127.0.0.1:8188`): encola los workflows, espera y posprocesa |
| `unpack_atlas.py` | Separa el atlas exportado en los PNG de `assets/sprites/` |
| `make_cracks.py` | Genera por código las 3 etapas de grieta de los bloques |

## Posprocesado (comfy_pipeline.js)

1. **Objetos**: quita el fondo por inundación desde los bordes, conserva solo el objeto más grande (fuera sombras y objetos sueltos), recorta y centra.
2. **Bloques**: toma el 45 % central de la imagen para que la textura quede con píxeles gordos.
3. Agrupa colores con k-means y asigna a cada grupo un color de la paleta sin desviar el tono.
4. Reduce al tamaño final por **voto mayoritario** por celda (no promedia, así no se apaga el contraste).
5. A los objetos les pone un **contorno** de 1 px (`#181425`).

## Cómo regenerar o añadir sprites

1. Añade o edita la entrada en `assets.json` (cambiar `seed` da otra variante).
2. Con ComfyUI abierto, pega `comfy_pipeline.js` en la consola de la página y ejecuta
   `await SpritePipeline.queueAll(assets, style)`; luego `await SpritePipeline.collect()` hasta que `pending` sea 0.
3. Cada asset genera 2 candidatos (~40 s en la 3060). Se elige el mejor, se empaqueta en un atlas
   (índices de paleta comprimidos + manifiesto + checksum) y se desempaqueta con
   `python3 tools/sprites/unpack_atlas.py atlas.json`.
4. Ejecuta las pruebas: comprueban que cada bioma, mejora y minero del balance tenga su sprite y el tamaño correcto.

## Tamaños

Bloques, íconos, personajes y reliquias: 32×32 · monedas y minerales: 16×16 · grietas: 32×32 (capa transparente).
