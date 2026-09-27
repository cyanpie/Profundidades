extends Node
## Guarda y carga la partida en user:// y calcula el progreso offline al abrir el juego.
## Con el argumento de línea de comandos `-- --no-save` no lee ni escribe nada (lo usan las pruebas).

const SAVE_PATH := "user://save.json"
## Subir este número al cambiar el formato y añadir la conversión en _migrate().
const SAVE_VERSION := 1
const AUTOSAVE_SECONDS := 15.0

## Resumen del progreso offline de esta sesión ({} si no hubo). La UI lo muestra al iniciar.
var offline_report: Dictionary = {}
var saving_enabled: bool = true


func _ready() -> void:
	saving_enabled = not OS.get_cmdline_user_args().has("--no-save")
	if not saving_enabled:
		return
	load_game()
	var timer := Timer.new()
	timer.wait_time = AUTOSAVE_SECONDS
	timer.autostart = true
	timer.timeout.connect(save_game)
	add_child(timer)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			save_game()


func save_game() -> void:
	if not saving_enabled:
		return
	var data := {
		"version": SAVE_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"state": GameState.to_dict(),
	}
	# Escritura atómica: primero a un temporal, luego se reemplaza el archivo real.
	var tmp_path := SAVE_PATH + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("No se pudo guardar: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data))
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp_path),
			ProjectSettings.globalize_path(SAVE_PATH))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not parsed is Dictionary:
		push_warning("Guardado ilegible; se empieza una partida nueva.")
		return
	var data := _migrate(parsed)
	GameState.from_dict(data.get("state", {}))
	var away := int(Time.get_unix_time_from_system()) - int(data.get("saved_at", 0))
	if away >= int(Balance.data["offline"]["min_seconds"]) and not GameState.dps.is_zero():
		offline_report = GameState.apply_offline(away)


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	GameState.new_game()


## Convierte guardados de versiones anteriores al formato actual.
func _migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 1))
	if version > SAVE_VERSION:
		push_warning("Guardado de una versión más nueva del juego (%d)." % version)
	# Ejemplo futuro: if version < 2: data["state"]["nuevo_campo"] = valor_por_defecto
	data["version"] = SAVE_VERSION
	return data
