# Profundidades

Idle de excavación en pixel art para Android, hecho en **Godot 4.7**. El diseño completo está en [`GDD.md`](GDD.md) y las convenciones de código en [`CLAUDE.md`](CLAUDE.md).

## Cómo abrirlo

1. Descarga Godot 4.7 (versión estándar, no .NET) desde [godotengine.org](https://godotengine.org/download).
2. En Godot: **Importar** → selecciona el `project.godot` de esta carpeta.
3. Pulsa **F5** para jugar. La ventana simula un celular vertical.

## Pruebas

Las pruebas cubren los números grandes, la economía, el guardado y la pantalla principal. El argumento `--no-save` evita que toquen tu partida guardada.

```
godot --headless res://tests/test_runner.tscn -- --no-save
```

Deben terminar con `0 fallos`.

## Estructura

| Carpeta | Contenido |
|---|---|
| `scripts/core/` | `BigNum` (números gigantes) y `Economy` (fórmulas puras del GDD §4) |
| `scripts/autoload/` | `Balance` (lee el JSON), `GameState` (estado y reglas), `SaveManager` (guardado y offline) |
| `scripts/main.gd` | Pantalla principal (UI armada por código mientras hay placeholders) |
| `data/balance.json` | **Todos** los números de balance: vida de bloques, oro, costos, mejoras, mineros, biomas |
| `data/translations.csv` | Textos en español e inglés |
| `assets/sprites/` | Arte pixel art (bloques, íconos, personajes, monedas, minerales, reliquias, grietas) |
| `tools/sprites/` | Pipeline para generar el arte con ComfyUI (ver su README) |
| `tests/` | Pruebas automáticas |

Para ajustar el balance no hace falta tocar código: se edita `data/balance.json` y se vuelve a jugar.

## Estado (v0.2 — con arte)

Hecho:
- Bloque que se rompe al tocarlo, con textura propia por bioma (3 variantes cada uno) y 3 etapas de grieta.
- Arte pixel art generado con ComfyUI en paleta Endesga 32: 54 sprites (bloques, 12 íconos de mejoras, 5 personajes, monedas, 9 minerales, 10 reliquias).
- Excavador animado junto al bloque, íconos en la tienda y moneda en el contador de oro.
- Profundidad, oro y los 5 biomas con aviso al cambiar de capa.
- 5 mejoras (pico, guantes, carretilla, casco, mapa) y 2 mineros (aprendiz, veterano).
- Guardado automático cada 15 s y al salir, con progreso offline (tope de 2 h, mejorable).
- Números grandes sin desbordes (probado hasta 10^500).

Pendiente (según GDD):
- Fuente pixel, animación de picar del excavador y sprites de UI (botones, paneles).
- Resto de mejoras y mineros, minerales, reliquias, dinamita y críticos.
- Prestigio (Nueva expedición).
- Anuncios recompensados (AdMob) y exportación a Android.
- Pantalla de Ajustes (sonido, idioma).
