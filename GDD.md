# Profundidades — Game Design Document (v0.1)

> Título provisional. Documento vivo: es la fuente de verdad para el código (sesiones de Claude Code) y para el arte (pipeline ComfyUI).

## 1. Resumen

| | |
|---|---|
| Género | Idle / incremental con toque activo (clicker) |
| Plataforma | Android (vertical) |
| Motor | Godot 4 (última versión estable) |
| Estilo | Pixel art, paleta fija Endesga 32 |
| Monetización | Anuncios recompensados (AdMob), sin anuncios forzados en el MVP |
| Gancho | "¿Qué hay más abajo?": cada capa revela un mundo nuevo, reliquias raras y secretos |

**Pitch:** Cavas hacia abajo bloque a bloque. Cada metro te acerca a biomas nuevos, minerales más valiosos y reliquias de una civilización olvidada. Contratas mineros que siguen cavando mientras no juegas.

## 2. Bucle principal

1. El jugador toca el bloque actual → le hace daño (`tap_damage`).
2. El bloque se rompe → suelta oro y, a veces, minerales o una reliquia.
3. Se avanza 1 metro → aparece el siguiente bloque (más resistente).
4. El oro compra mejoras (más daño por toque) y mineros (daño por segundo automático).
5. Con la app cerrada, los mineros siguen produciendo (progreso offline).

## 3. Biomas (MVP: 5)

| # | Bioma | Profundidad | Minerales | Paleta dominante |
|---|---|---|---|---|
| 1 | Tierra | 0–100 m | Cobre, hierro | Marrones, verdes |
| 2 | Cavernas de cristal | 100–300 m | Cuarzo, amatista | Azules, violetas |
| 3 | Río de lava | 300–600 m | Obsidiana, rubí | Rojos, naranjas, negro |
| 4 | Ruinas antiguas | 600–1000 m | Oro antiguo, jade | Arena, verde jade |
| 5 | El Abismo | 1000 m+ | Esencia oscura | Negros, violeta brillante |

Al entrar a un bioma nuevo: transición visual + mensaje ("Has llegado a las Cavernas de cristal").

## 4. Economía (valores iniciales para balancear)

- **HP del bloque:** `hp(m) = 5 × 1.07^m`
- **Oro por bloque:** `oro(m) = 2 × 1.065^m` (crece un poco más lento que el HP → presión para mejorar)
- **Costo de mejora nivel n:** `costo = base × 1.15^n`
- **Mineros:** cada tipo aporta DPS fijo por unidad; costo con factor 1.15 por unidad comprada
- **Offline:** 100 % del DPS de mineros, tope 2 h (mejorable hasta 8 h)
- **Prestigio (Nueva expedición):** disponible desde 300 m. Otorga *Fragmentos antiguos* = `floor(sqrt(profundidad_max / 50))`; cada fragmento da +10 % de producción permanente. Se reinicia oro, mejoras, mineros y profundidad; se conservan reliquias y fragmentos.

> Todos los valores viven en `data/balance.json` (no hardcodeados) para iterar el balance sin tocar lógica. Si cambian allí, actualizar esta sección.

## 5. Mejoras (MVP: 12)

| Mejora | Efecto |
|---|---|
| Pico reforzado | +daño por toque |
| Guantes de minero | +% daño por toque |
| Taladro manual | toque crítico (probabilidad) |
| Dinamita | habilidad activa: daño masivo, cooldown |
| Lámpara de carburo | +% probabilidad de minerales |
| Carretilla | +% oro por bloque |
| Detector de metales | +% probabilidad de reliquias |
| Mapa antiguo | +tope de horas offline |
| Casco con luz | +% daño de mineros |
| Raíles | +% velocidad de mineros |
| Bomba de agua | +% oro en biomas profundos |
| Contrato sindical | −% costo de mineros |

## 6. Mineros (MVP: 4)

| Minero | Rol |
|---|---|
| Aprendiz | DPS bajo, barato |
| Veterano | DPS medio |
| Topo mecánico | DPS alto |
| Gólem de piedra | DPS muy alto, se desbloquea en Ruinas |

## 7. Reliquias (MVP: 10)

Coleccionables raros (probabilidad base ~0,5 % por bloque, aumenta con mejoras). Cada una da un bonus permanente pequeño y tiene una línea de lore. Pantalla de colección con huecos visibles para las que faltan (motiva completar).

## 8. Anuncios (recompensados, opcionales)

- **x2 producción** durante 30 min
- **Cofre enterrado** que aparece al romper bloques; se abre viendo un anuncio
- **x2 ganancias offline** al volver a la app

Regla: ningún anuncio interrumpe el juego sin que el jugador lo pida.

## 9. Pantallas / UI

1. **Principal:** bloque actual al centro, contador de profundidad arriba, oro y gemas, botón de dinamita, acceso a paneles.
2. **Panel de mejoras** (pestaña inferior)
3. **Panel de mineros** (pestaña inferior)
4. **Colección de reliquias**
5. **Prestigio / Nueva expedición**
6. **Ajustes** (sonido, idioma)
7. **Popup de ganancias offline**

## 10. Especificación técnica de arte

- Resolución base del juego: **270×480** escalada ×4 a 1080×1920 (filtro *nearest*, sin suavizado).
- Paleta: **Endesga 32** estricta en todos los sprites.
- Tamaños: bloques 32×32 · íconos 32×32 · minerales y monedas 16×16 · partículas 8×8.
- Fondos de sprites transparentes (PNG).
- Pipeline: ComfyUI (SDXL + LoRA pixel art) → quitar fondo → reescalar a tamaño final → cuantizar a la paleta → spritesheet.

### Lista de assets MVP

| Categoría | Cantidad |
|---|---|
| Bloques de terreno | 5 biomas × (base + 2 variaciones + 3 etapas de grieta) = 30 |
| Minerales | ~12 |
| Excavador (idle + picar 4–6 frames) | 1 personaje |
| Mineros | 4 |
| Íconos de mejoras | 12 |
| Monedas (oro, gemas, fragmentos) | 3 |
| Reliquias | 10 |
| UI (botones, paneles, barras, marcos 9-slice) | ~10 |
| Efectos (partículas, brillos) | ~5 |

## 11. Fuera del MVP (ideas para después)

Eventos temporales, más biomas, jefes de capa (bloques especiales), logros de Google Play, compras integradas (quitar anuncios, paquetes de gemas).
