extends Node
## Carga data/balance.json una sola vez. Toda la lógica lee los números de balance desde aquí.

const PATH := "res://data/balance.json"

var data: Dictionary = {}


func _init() -> void:
	# Se carga en _init para que esté listo antes del _ready de los demás autoloads.
	data = load_file(PATH)


static func load_file(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("No se pudo leer %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("%s no es un JSON válido" % path)
	return {}
