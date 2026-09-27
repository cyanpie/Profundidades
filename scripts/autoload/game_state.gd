extends Node
## Estado de la partida y reglas en tiempo real (toques, mineros, compras).
## La matemática vive en Economy; aquí solo se aplica y se avisa a la UI por señales.

signal gold_changed
signal block_changed
signal block_broken(gold_gain: BigNum, count: int)
signal depth_changed
signal biome_changed(index: int)
signal shop_changed

## Tope de bloques rotos por frame, para que un DPS enorme no congele el juego.
const MAX_BLOCKS_PER_FRAME := 50

var depth: int = 0
var max_depth: int = 0
var gold: BigNum = BigNum.zero()
var block_hp_left: BigNum = BigNum.zero()
var upgrade_levels: Dictionary = {}
var miner_counts: Dictionary = {}
var total_taps: int = 0

# Valores derivados; se recalculan tras cada compra o carga.
var tap_damage: BigNum = BigNum.zero()
var dps: BigNum = BigNum.zero()
var gold_mult: float = 1.0

var _bal: Dictionary


func _ready() -> void:
	_bal = Balance.data
	new_game()


func _process(delta: float) -> void:
	if not dps.is_zero():
		_apply_damage(dps.mul_f(delta))


func new_game() -> void:
	depth = 0
	max_depth = 0
	gold = BigNum.zero()
	upgrade_levels = {}
	miner_counts = {}
	total_taps = 0
	block_hp_left = Economy.block_hp(_bal, depth)
	_recalc()
	_emit_all()


func tap() -> void:
	total_taps += 1
	_apply_damage(tap_damage)


# --- Consultas para la UI ---

func block_max_hp() -> BigNum:
	return Economy.block_hp(_bal, depth)


func block_hp_fraction() -> float:
	return clampf(block_hp_left.div(block_max_hp()).to_float(), 0.0, 1.0)


func biome_index() -> int:
	return Economy.biome_index(_bal, depth)


func biome() -> Dictionary:
	return _bal["biomes"][biome_index()]


func upgrade_defs() -> Array:
	return _bal["upgrades"]


func miner_defs() -> Array:
	return _bal["miners"]


func upgrade_level(id: String) -> int:
	return int(upgrade_levels.get(id, 0))


func miner_count(id: String) -> int:
	return int(miner_counts.get(id, 0))


func upgrade_cost(id: String) -> BigNum:
	return Economy.upgrade_cost(Economy.find_def(upgrade_defs(), id), upgrade_level(id))


func miner_cost(id: String) -> BigNum:
	return Economy.miner_cost(Economy.find_def(miner_defs(), id), miner_count(id))


func is_upgrade_maxed(id: String) -> bool:
	return Economy.is_maxed(Economy.find_def(upgrade_defs(), id), upgrade_level(id))


func can_buy_upgrade(id: String) -> bool:
	return not is_upgrade_maxed(id) and gold.gte(upgrade_cost(id))


func can_buy_miner(id: String) -> bool:
	return gold.gte(miner_cost(id))


# --- Compras ---

func buy_upgrade(id: String) -> bool:
	if not can_buy_upgrade(id):
		return false
	gold = gold.sub(upgrade_cost(id))
	upgrade_levels[id] = upgrade_level(id) + 1
	_after_purchase()
	return true


func buy_miner(id: String) -> bool:
	if not can_buy_miner(id):
		return false
	gold = gold.sub(miner_cost(id))
	miner_counts[id] = miner_count(id) + 1
	_after_purchase()
	return true


# --- Progreso offline ---

## Aplica el trabajo de los mineros durante `seconds` (con tope) y devuelve un resumen.
func apply_offline(seconds: float) -> Dictionary:
	var capped := minf(seconds, Economy.offline_cap_seconds(_bal, upgrade_levels))
	var start_depth := depth
	var r := Economy.apply_damage(_bal, depth, block_hp_left, dps.mul_f(capped), gold_mult,
			int(_bal["offline"]["max_blocks"]))
	depth = r["depth"]
	max_depth = maxi(max_depth, depth)
	block_hp_left = r["hp"]
	gold = gold.add(r["gold"])
	_emit_all()
	return {"seconds": capped, "gold": r["gold"], "meters": depth - start_depth}


# --- Guardado ---

func to_dict() -> Dictionary:
	return {
		"depth": depth,
		"max_depth": max_depth,
		"gold": gold.to_dict(),
		"block_hp_left": block_hp_left.to_dict(),
		"upgrades": upgrade_levels.duplicate(),
		"miners": miner_counts.duplicate(),
		"total_taps": total_taps,
	}


func from_dict(d: Dictionary) -> void:
	depth = int(d.get("depth", 0))
	max_depth = int(d.get("max_depth", depth))
	gold = BigNum.from_dict(d.get("gold"))
	upgrade_levels = _int_dict(d.get("upgrades", {}))
	miner_counts = _int_dict(d.get("miners", {}))
	total_taps = int(d.get("total_taps", 0))
	block_hp_left = BigNum.from_dict(d.get("block_hp_left"))
	if block_hp_left.is_zero() or block_hp_left.gt(block_max_hp()):
		block_hp_left = block_max_hp()
	_recalc()
	_emit_all()


# --- Internos ---

func _apply_damage(damage: BigNum) -> void:
	var prev_biome := biome_index()
	var r := Economy.apply_damage(_bal, depth, block_hp_left, damage, gold_mult, MAX_BLOCKS_PER_FRAME)
	block_hp_left = r["hp"]
	var blocks: int = r["blocks"]
	if blocks > 0:
		depth = r["depth"]
		max_depth = maxi(max_depth, depth)
		gold = gold.add(r["gold"])
		block_broken.emit(r["gold"], blocks)
		depth_changed.emit()
		gold_changed.emit()
		var new_biome := biome_index()
		if new_biome != prev_biome:
			biome_changed.emit(new_biome)
	block_changed.emit()


func _after_purchase() -> void:
	_recalc()
	gold_changed.emit()
	shop_changed.emit()


func _recalc() -> void:
	tap_damage = Economy.tap_damage(_bal, upgrade_levels)
	dps = Economy.miners_dps(_bal, miner_counts, upgrade_levels)
	gold_mult = Economy.gold_multiplier(_bal, upgrade_levels)


func _emit_all() -> void:
	gold_changed.emit()
	depth_changed.emit()
	block_changed.emit()
	shop_changed.emit()


## JSON devuelve números como float; los niveles se guardan como enteros.
static func _int_dict(src: Variant) -> Dictionary:
	var out := {}
	if src is Dictionary:
		for k: Variant in src:
			out[str(k)] = int(src[k])
	return out
