# Instrucciones para Claude Code — proyecto "Profundidades"

Juego idle/clicker de excavación para Android, en Godot 4. La especificación completa está en `GDD.md`: léela antes de cualquier tarea y mantenla como fuente de verdad. Si una tarea obliga a desviarse del GDD, dilo y propón el cambio al documento.

## Convenciones
- Godot 4 (última estable), GDScript con tipado estático.
- Resolución base 270×480, stretch mode `viewport`, escalado entero, filtro de texturas `nearest`.
- Todos los números de balance (HP, costos, multiplicadores) viven en `data/balance.json` o recursos `.tres`, nunca hardcodeados en la lógica.
- Números grandes: usar un tipo propio (mantisa + exponente) desde el inicio; los idle games desbordan `float`/`int` rápido.
- Guardado local en `user://` con versión de formato para migraciones.
- Mientras no exista el arte, usar placeholders de colores planos con el tamaño final de cada sprite (ver GDD §10).
- Idioma del juego: español por defecto, textos en archivo de traducción (preparado para inglés).

## Estructura sugerida
```
scenes/      escenas (.tscn)
scripts/     lógica (.gd)
data/        balance y configuración
assets/      sprites, audio, fuentes
tests/       pruebas de la economía y el guardado
```

## Forma de trabajo
- Commits pequeños y descriptivos, en español.
- Antes de cerrar una tarea: que el proyecto abra sin errores y que las pruebas pasen.
