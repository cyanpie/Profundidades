extends Control
## Pantalla principal (GDD §9.1-9.3, §9.7). La UI se arma por código; los sprites salen de
## assets/sprites (generados con tools/sprites). Si falta un sprite se usa un color de respaldo.

const BLOCK_SIZE := 32
const BLOCK_SCALE := 3
const CHARACTER_SCALE := 2
const SPRITES := "res://assets/sprites/"
## Variantes de bloque por bioma (assets/sprites/blocks/<bioma>_<variante>.png).
const BLOCK_VARIANTS: Array[String] = ["a", "b", "c"]
## Oscurecimiento del color de respaldo en las 3 etapas de grieta (GDD §10).
const CRACK_DARKEN: Array[float] = [0.0, 0.18, 0.34, 0.5]
const MAX_FLOATING_LABELS := 12

var _depth_label: Label
var _biome_label: Label
var _gold_label: Label
var _stats_label: Label
var _block: Control
var _block_fallback: ColorRect
var _block_texture: TextureRect
var _crack: TextureRect
var _crack_textures: Array[Texture2D] = []
var _excavator: TextureRect
var _block_holder: Control
var _hp_bar: ProgressBar
var _float_layer: Control
var _banner: Label
var _upgrade_rows: Dictionary = {}
var _miner_rows: Dictionary = {}


func _ready() -> void:
	# Español por defecto (GDD); el selector de idioma llegará con la pantalla de Ajustes.
	TranslationServer.set_locale("es")
	theme = _make_theme()
	_build_ui()
	GameState.gold_changed.connect(_on_gold_changed)
	GameState.depth_changed.connect(_on_depth_changed)
	GameState.block_changed.connect(_on_block_changed)
	GameState.block_broken.connect(_on_block_broken)
	GameState.biome_changed.connect(_on_biome_changed)
	GameState.shop_changed.connect(_refresh_shop)
	_on_depth_changed()
	_on_gold_changed()
	_on_block_changed()
	_refresh_shop()
	if not SaveManager.offline_report.is_empty():
		_show_offline_popup.call_deferred(SaveManager.offline_report)


# --- Construcción de la UI ---

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color("#181425")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	margin.add_child(root)

	# Cabecera: profundidad, bioma, oro y estadísticas.
	_depth_label = _label(root, 20)
	_depth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_biome_label = _label(root, 10, Color("#8b9bb4"))
	_biome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var gold_row := HBoxContainer.new()
	gold_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gold_row.add_theme_constant_override("separation", 3)
	root.add_child(gold_row)
	gold_row.add_child(_sprite("currency/oro.png", 1))
	_gold_label = _label(gold_row, 12, Color("#feae34"))
	_stats_label = _label(root, 8, Color("#c0cbdc"))
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Zona del bloque: ocupa el espacio libre y todo es tocable.
	var block_area := Button.new()
	block_area.flat = true
	block_area.focus_mode = Control.FOCUS_NONE
	block_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	block_area.custom_minimum_size = Vector2(0, 150)
	block_area.button_down.connect(_on_block_pressed)
	root.add_child(block_area)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block_area.add_child(center)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	center.add_child(column)

	var side := BLOCK_SIZE * BLOCK_SCALE
	_block_holder = Control.new()
	_block_holder.custom_minimum_size = Vector2(side, side)
	_block_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_block_holder)

	# El bloque es un contenedor: color de respaldo + sprite del bioma + capa de grietas.
	_block = Control.new()
	_block.size = Vector2(side, side)
	_block.pivot_offset = Vector2(side, side) / 2.0
	_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_block_holder.add_child(_block)
	_block_fallback = ColorRect.new()
	_block_fallback.size = Vector2(side, side)
	_block_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_block.add_child(_block_fallback)
	_block_texture = _sprite("", BLOCK_SCALE)
	_block.add_child(_block_texture)
	_crack = _sprite("", BLOCK_SCALE)
	_block.add_child(_crack)
	for i in range(1, 4):
		_crack_textures.append(_load_texture("cracks/grieta_%d.png" % i))

	# El excavador a la izquierda del bloque; da un saltito con cada toque.
	_excavator = _sprite("characters/excavador.png", CHARACTER_SCALE)
	_excavator.position = Vector2(-BLOCK_SIZE * CHARACTER_SCALE - 4, side - BLOCK_SIZE * CHARACTER_SCALE)
	_excavator.pivot_offset = Vector2(BLOCK_SIZE, BLOCK_SIZE * 2) * CHARACTER_SCALE / 2.0
	_block_holder.add_child(_excavator)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(side, 6)
	_hp_bar.show_percentage = false
	_hp_bar.max_value = 1.0
	_hp_bar.step = 0.0
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_hp_bar)

	_float_layer = Control.new()
	_float_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block_area.add_child(_float_layer)

	_banner = _label(block_area, 10, Color("#fee761"))
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0

	# Tienda: pestañas de mejoras y mineros.
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 190)
	root.add_child(tabs)

	var upgrades_list := _scroll_list(tabs, tr("UI_TAB_UPGRADES"))
	for def: Dictionary in GameState.upgrade_defs():
		var id: String = def["id"]
		_upgrade_rows[id] = _shop_row(upgrades_list, "UPG_" + id.to_upper(), "upgrades/%s.png" % id,
				func() -> void: GameState.buy_upgrade(id))

	var miners_list := _scroll_list(tabs, tr("UI_TAB_MINERS"))
	for def: Dictionary in GameState.miner_defs():
		var id: String = def["id"]
		_miner_rows[id] = _shop_row(miners_list, "MINER_" + id.to_upper(), "characters/%s.png" % id,
				func() -> void: GameState.buy_miner(id))


func _scroll_list(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)
	return list


## Fila de la tienda: ícono, nombre + descripción/nivel y botón de compra con el costo.
func _shop_row(parent: Control, key: String, icon_path: String, on_buy: Callable) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	row.add_child(_sprite(icon_path, 1))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)
	var name_label := _label(info, 10)
	name_label.text = tr(key)
	var detail := _label(info, 8, Color("#8b9bb4"))
	var button := Button.new()
	button.custom_minimum_size = Vector2(64, 24)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_buy)
	row.add_child(button)
	return {"detail": detail, "button": button, "desc": tr(key + "_DESC")}


func _label(parent: Node, font_size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## TextureRect de un sprite a escala entera (nearest). Si el archivo no existe queda vacío.
func _sprite(path: String, scale_factor: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = _load_texture(path) if not path.is_empty() else null
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var base := r.texture.get_size() if r.texture else Vector2(BLOCK_SIZE, BLOCK_SIZE)
	r.custom_minimum_size = base * scale_factor
	r.size = base * scale_factor
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _load_texture(path: String) -> Texture2D:
	var full := SPRITES + path
	return load(full) if ResourceLoader.exists(full) else null


func _block_texture_for(depth: int, biome_id: String) -> Texture2D:
	# Variante pseudoaleatoria pero fija por metro: el mismo metro siempre se ve igual.
	var index := posmod((depth * 1103515245 + 12345) >> 16, BLOCK_VARIANTS.size())
	return _load_texture("blocks/%s_%s.png" % [biome_id, BLOCK_VARIANTS[index]])


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 10
	# Compra disponible en amarillo, no disponible en gris apagado: se distingue de un vistazo.
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(state, "Button", Color("#fee761"))
	t.set_color("font_disabled_color", "Button", Color("#5a6988"))
	return t


# --- Reacciones al estado ---

func _on_block_pressed() -> void:
	GameState.tap()
	var tween := create_tween()
	_block.scale = Vector2(0.92, 0.92)
	tween.tween_property(_block, "scale", Vector2.ONE, 0.08)
	var hop := create_tween()
	_excavator.scale = Vector2(1.1, 0.9)
	hop.tween_property(_excavator, "scale", Vector2.ONE, 0.1)


func _on_depth_changed() -> void:
	_depth_label.text = tr("UI_DEPTH") % GameState.depth
	var biome := GameState.biome()
	_biome_label.text = tr(biome["name_key"])
	_block_texture.texture = _block_texture_for(GameState.depth, biome["id"])
	_on_block_changed()


func _on_gold_changed() -> void:
	_gold_label.text = tr("UI_GOLD") % GameState.gold.format()
	_update_affordability()


func _on_block_changed() -> void:
	var fraction := GameState.block_hp_fraction()
	_hp_bar.value = fraction
	var stage := clampi(int((1.0 - fraction) * CRACK_DARKEN.size()), 0, CRACK_DARKEN.size() - 1)
	var biome := GameState.biome()
	_block_fallback.color = Color(biome["color"]).darkened(CRACK_DARKEN[stage])
	_block_fallback.visible = _block_texture.texture == null
	_crack.texture = _crack_textures[stage - 1] if stage > 0 else null


func _on_block_broken(gold_gain: BigNum, _count: int) -> void:
	if _float_layer.get_child_count() >= MAX_FLOATING_LABELS:
		return
	var l := _label(_float_layer, 10, Color("#feae34"))
	l.text = "+" + gold_gain.format()
	var block_pos := _block_holder.global_position - _float_layer.global_position
	l.position = block_pos + Vector2(randf_range(-10, BLOCK_SIZE * BLOCK_SCALE - 10), randf_range(-12, 10))
	var tween := create_tween().set_parallel()
	tween.tween_property(l, "position:y", l.position.y - 30, 0.7)
	tween.tween_property(l, "modulate:a", 0.0, 0.7)
	tween.chain().tween_callback(l.queue_free)


func _on_biome_changed(index: int) -> void:
	var biome: Dictionary = Balance.data["biomes"][index]
	_banner.text = tr("UI_NEW_BIOME") % tr(biome["name_key"])
	var tween := create_tween()
	_banner.modulate.a = 1.0
	tween.tween_interval(2.0)
	tween.tween_property(_banner, "modulate:a", 0.0, 0.6)


func _refresh_shop() -> void:
	_stats_label.text = "%s   ·   %s" % [
		tr("UI_TAP_DAMAGE") % GameState.tap_damage.format(),
		tr("UI_DPS") % GameState.dps.format(),
	]
	for id: String in _upgrade_rows:
		var row: Dictionary = _upgrade_rows[id]
		row["detail"].text = "%s · %s" % [tr("UI_LEVEL") % GameState.upgrade_level(id), row["desc"]]
		row["button"].text = tr("UI_MAX") if GameState.is_upgrade_maxed(id) else GameState.upgrade_cost(id).format()
	for id: String in _miner_rows:
		var row: Dictionary = _miner_rows[id]
		row["detail"].text = "%s · %s" % [tr("UI_OWNED") % GameState.miner_count(id), row["desc"]]
		row["button"].text = GameState.miner_cost(id).format()
	_update_affordability()


func _update_affordability() -> void:
	for id: String in _upgrade_rows:
		_upgrade_rows[id]["button"].disabled = not GameState.can_buy_upgrade(id)
	for id: String in _miner_rows:
		_miner_rows[id]["button"].disabled = not GameState.can_buy_miner(id)


func _show_offline_popup(report: Dictionary) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = tr("UI_OFFLINE_TITLE")
	dialog.ok_button_text = tr("UI_OK")
	dialog.dialog_text = tr("UI_OFFLINE_BODY") % [
		report["meters"], (report["gold"] as BigNum).format(), _format_duration(report["seconds"])]
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _format_duration(seconds: float) -> String:
	var total_minutes := floori(seconds / 60.0)
	var hours := floori(total_minutes / 60.0)
	var minutes := total_minutes % 60
	if hours > 0:
		return tr("UI_HOURS_MINUTES") % [hours, minutes]
	return tr("UI_MINUTES") % minutes
