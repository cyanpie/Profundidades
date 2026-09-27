extends Node
## Pruebas de la economía, el guardado y la pantalla principal.
## Ejecutar (sin tocar tu partida guardada):
##   godot --headless res://tests/test_runner.tscn -- --no-save
## Sale con código 0 si todo pasa y 1 si algo falla.

var _failures: int = 0
var _checks: int = 0
var _bal: Dictionary


func _ready() -> void:
	if SaveManager.saving_enabled:
		push_error("Ejecuta las pruebas con '-- --no-save' para no sobrescribir la partida real.")
		get_tree().quit(1)
		return
	_bal = Balance.data
	await _run_all()
	print("\n%d comprobaciones, %d fallos" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _run_all() -> void:
	_test_big_num_basics()
	_test_big_num_format()
	_test_economy_formulas()
	_test_apply_damage()
	_test_game_state_flow()
	_test_offline()
	_test_save_roundtrip()
	await _test_main_scene()


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("  FALLO: ", what)


func _near(a: float, b: float, rel: float = 1e-9) -> bool:
	return absf(a - b) <= rel * maxf(absf(a), absf(b)) + 1e-12


# --- BigNum ---

func _test_big_num_basics() -> void:
	print("BigNum: operaciones")
	var a := BigNum.from_float(1234.5)
	_check(a.e == 3 and _near(a.m, 1.2345), "normaliza 1234.5")
	_check(_near(a.add(BigNum.from_float(765.5)).to_float(), 2000.0), "suma")
	_check(_near(a.sub(BigNum.from_float(234.5)).to_float(), 1000.0), "resta")
	_check(BigNum.from_float(5).sub(BigNum.from_float(5)).is_zero(), "resta a cero")
	_check(_near(a.mul(BigNum.from_float(2)).to_float(), 2469.0), "multiplica")
	_check(_near(a.div(BigNum.from_float(10)).to_float(), 123.45), "divide")
	var huge := BigNum.pow_f(10.0, 500.0)
	_check(huge.e == 500 and _near(huge.m, 1.0, 1e-6), "10^500 sin desbordar")
	_check(huge.add(BigNum.from_float(1)).cmp(huge) == 0, "sumar 1 a 10^500 no cambia nada")
	_check(huge.gt(BigNum.pow_f(10.0, 499.0)), "compara exponentes")
	_check(BigNum.from_float(-3).lt(BigNum.from_float(2)), "compara negativos")
	_check(BigNum.from_float(0.5).lt(BigNum.from_float(1)), "compara menores a 1")
	var restored := BigNum.from_dict(JSON.parse_string(JSON.stringify(huge.to_dict())))
	_check(restored.cmp(huge) == 0, "sobrevive a JSON")


func _test_big_num_format() -> void:
	print("BigNum: formato")
	var cases := {
		0.0: "0", 7.0: "7", 999.0: "999", 1000.0: "1.00K", 1999.0: "1.99K",
		45600.0: "45.6K", 123456789.0: "123M", 1.5e12: "1.50T", 1e15: "1.00aa", 2.5e18: "2.50ab",
	}
	for value: float in cases:
		var got := BigNum.from_float(value).format()
		_check(got == cases[value], "format(%s) = %s (se esperaba %s)" % [value, got, cases[value]])


# --- Economía ---

func _test_economy_formulas() -> void:
	print("Economía: fórmulas")
	_check(_near(Economy.block_hp(_bal, 0).to_float(), 5.0), "vida del primer bloque")
	_check(_near(Economy.block_hp(_bal, 10).to_float(), 5.0 * pow(1.07, 10), 1e-6), "vida a 10 m")
	_check(_near(Economy.block_gold(_bal, 0, 1.0).to_float(), 2.0), "oro del primer bloque")
	var pico := Economy.find_def(_bal["upgrades"], "pico_reforzado")
	_check(_near(Economy.upgrade_cost(pico, 3).to_float(), 10.0 * pow(1.15, 3), 1e-6), "costo mejora nivel 3")
	_check(_near(Economy.tap_damage(_bal, {}).to_float(), 1.0), "daño base")
	_check(_near(Economy.tap_damage(_bal, {"pico_reforzado": 4, "guantes": 5}).to_float(), 5.0 * 1.5, 1e-6),
			"daño con pico 4 y guantes 5")
	_check(_near(Economy.miners_dps(_bal, {"aprendiz": 3, "veterano": 1}, {}).to_float(), 11.0), "DPS mineros")
	_check(Economy.biome_index(_bal, 0) == 0 and Economy.biome_index(_bal, 100) == 1
			and Economy.biome_index(_bal, 5000) == 4, "biomas por profundidad")
	var mapa := Economy.find_def(_bal["upgrades"], "mapa_antiguo")
	_check(Economy.is_maxed(mapa, 12) and not Economy.is_maxed(mapa, 11), "tope de nivel")


func _test_apply_damage() -> void:
	print("Economía: aplicar daño")
	var hp0 := Economy.block_hp(_bal, 0)
	var r := Economy.apply_damage(_bal, 0, hp0, BigNum.from_float(3), 1.0, 50)
	_check(r["blocks"] == 0 and _near((r["hp"] as BigNum).to_float(), 2.0), "daño parcial")
	r = Economy.apply_damage(_bal, 0, hp0, BigNum.from_float(5), 1.0, 50)
	_check(r["blocks"] == 1 and r["depth"] == 1, "rompe exacto")
	r = Economy.apply_damage(_bal, 0, hp0, BigNum.pow_f(10.0, 50.0), 1.0, 50)
	_check(r["blocks"] == 50 and r["depth"] == 50, "respeta el tope de bloques")
	_check((r["hp"] as BigNum).cmp(Economy.block_hp(_bal, 50)) == 0, "con tope, el bloque queda entero")


# --- Estado de juego ---

func _test_game_state_flow() -> void:
	print("GameState: flujo de juego")
	GameState.new_game()
	for i in 200:
		GameState.tap()
	_check(GameState.depth > 0, "tocar hace avanzar (%d m)" % GameState.depth)
	_check(GameState.gold.gt(BigNum.zero()), "tocar da oro")
	GameState.gold = BigNum.zero()
	_check(not GameState.buy_miner("veterano"), "no compra sin oro")
	GameState.gold = BigNum.from_float(1e6)
	_check(GameState.buy_upgrade("pico_reforzado"), "compra mejora")
	_check(GameState.upgrade_level("pico_reforzado") == 1, "sube nivel")
	_check(_near(GameState.tap_damage.to_float(), 2.0), "el daño se recalcula")
	_check(GameState.buy_miner("aprendiz"), "compra minero")
	_check(GameState.dps.gt(BigNum.zero()), "hay DPS")
	_check(not GameState.gold.is_negative(), "el oro nunca queda negativo")
	for i in 12:
		GameState.buy_upgrade("mapa_antiguo")
	_check(GameState.is_upgrade_maxed("mapa_antiguo") and not GameState.buy_upgrade("mapa_antiguo"),
			"no pasa del nivel máximo")


func _test_offline() -> void:
	print("GameState: progreso offline")
	GameState.new_game()
	GameState.gold = BigNum.from_float(100)
	GameState.buy_miner("aprendiz")
	var report := GameState.apply_offline(3600.0)
	_check(report["meters"] > 0, "cava offline (%d m en 1 h)" % report["meters"])
	_check((report["gold"] as BigNum).gt(BigNum.zero()), "gana oro offline")
	var capped := GameState.apply_offline(1e9)
	_check(_near(capped["seconds"], 2.0 * 3600.0), "respeta el tope de 2 h")


func _test_save_roundtrip() -> void:
	print("Guardado: ida y vuelta")
	GameState.new_game()
	GameState.gold = BigNum.pow_f(10.0, 42.0)
	GameState.buy_upgrade("guantes")
	GameState.gold = BigNum.from_float(1e6)
	GameState.buy_miner("veterano")
	GameState.tap()
	var saved := GameState.to_dict()
	var json := JSON.stringify(saved)
	GameState.new_game()
	GameState.from_dict(JSON.parse_string(json))
	_check(GameState.upgrade_level("guantes") == 1, "conserva mejoras")
	_check(GameState.miner_count("veterano") == 1, "conserva mineros")
	_check(GameState.gold.cmp(BigNum.from_dict(saved["gold"])) == 0, "conserva oro")
	_check(GameState.dps.gt(BigNum.zero()), "recalcula derivados al cargar")
	GameState.from_dict({})
	_check(GameState.depth == 0 and GameState.block_hp_left.gt(BigNum.zero()), "tolera guardado vacío")


# --- UI ---

func _test_main_scene() -> void:
	print("UI: pantalla principal")
	GameState.new_game()
	var main: Control = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	for i in 30:
		main._on_block_pressed()
	GameState.gold = BigNum.from_float(1e9)
	GameState.buy_upgrade("carretilla")
	GameState.depth = 99
	GameState.block_hp_left = BigNum.from_float(1)
	GameState.tap()
	for i in 5:
		await get_tree().process_frame
	_check(GameState.biome_index() == 1, "cambia de bioma en la pantalla")
	main._show_offline_popup({"meters": 12, "gold": BigNum.from_float(3400), "seconds": 5000.0})
	await get_tree().process_frame
	_check(main._gold_label.text.begins_with(tr("UI_GOLD").split(":")[0]), "la UI muestra el oro")
	main.queue_free()
	await get_tree().process_frame
