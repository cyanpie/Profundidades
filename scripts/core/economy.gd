class_name Economy
extends RefCounted
## Fórmulas puras de la economía (GDD §4). No guardan estado: todo entra por parámetros,
## así se pueden probar sin autoloads y reutilizar para el progreso offline.
## Los números salen de data/balance.json.


static func block_hp(bal: Dictionary, depth: int) -> BigNum:
	var b: Dictionary = bal["block"]
	return BigNum.pow_f(float(b["hp_growth"]), float(depth)).mul_f(float(b["hp_base"]))


static func block_gold(bal: Dictionary, depth: int, gold_mult: float) -> BigNum:
	var b: Dictionary = bal["block"]
	return BigNum.pow_f(float(b["gold_growth"]), float(depth)).mul_f(float(b["gold_base"]) * gold_mult)


static func find_def(defs: Array, id: String) -> Dictionary:
	for def: Dictionary in defs:
		if def["id"] == id:
			return def
	return {}


static func upgrade_cost(def: Dictionary, level: int) -> BigNum:
	return BigNum.pow_f(float(def["cost_growth"]), float(level)).mul_f(float(def["base_cost"]))


static func miner_cost(def: Dictionary, owned: int) -> BigNum:
	return BigNum.pow_f(float(def["cost_growth"]), float(owned)).mul_f(float(def["base_cost"]))


static func is_maxed(def: Dictionary, level: int) -> bool:
	return def.has("max_level") and level >= int(def["max_level"])


## Suma el aporte de todas las mejoras con un tipo de efecto dado.
static func effect_total(bal: Dictionary, levels: Dictionary, effect: String) -> float:
	var total := 0.0
	for def: Dictionary in bal["upgrades"]:
		if def["effect"] == effect:
			total += float(def["value"]) * int(levels.get(def["id"], 0))
	return total


static func tap_damage(bal: Dictionary, levels: Dictionary) -> BigNum:
	var flat := float(bal["tap"]["base_damage"]) + effect_total(bal, levels, "tap_flat")
	var pct := 1.0 + effect_total(bal, levels, "tap_pct")
	return BigNum.from_float(flat * pct)


static func gold_multiplier(bal: Dictionary, levels: Dictionary) -> float:
	return 1.0 + effect_total(bal, levels, "gold_pct")


static func miners_dps(bal: Dictionary, counts: Dictionary, levels: Dictionary) -> BigNum:
	var total := BigNum.zero()
	for def: Dictionary in bal["miners"]:
		var owned := int(counts.get(def["id"], 0))
		if owned > 0:
			total = total.add(BigNum.from_float(float(def["dps"]) * owned))
	return total.mul_f(1.0 + effect_total(bal, levels, "miner_pct"))


static func offline_cap_seconds(bal: Dictionary, levels: Dictionary) -> float:
	var hours := float(bal["offline"]["base_hours"]) + effect_total(bal, levels, "offline_hours")
	return hours * 3600.0


## Índice del bioma que corresponde a una profundidad (GDD §3).
static func biome_index(bal: Dictionary, depth: int) -> int:
	var index := 0
	var biomes: Array = bal["biomes"]
	for i in biomes.size():
		if depth >= int(biomes[i]["from_depth"]):
			index = i
	return index


## Aplica daño al bloque actual y rompe tantos bloques como alcance, hasta max_blocks.
## Si se llega al tope, el daño sobrante se descarta.
## Devuelve {"depth": int, "hp": BigNum (vida restante del bloque actual), "gold": BigNum, "blocks": int}.
static func apply_damage(bal: Dictionary, depth: int, hp_left: BigNum, damage: BigNum,
		gold_mult: float, max_blocks: int) -> Dictionary:
	var remaining := damage.copy()
	var d := depth
	var hp := hp_left.copy()
	var gold := BigNum.zero()
	var blocks := 0
	while blocks < max_blocks and remaining.gte(hp):
		remaining = remaining.sub(hp)
		gold = gold.add(block_gold(bal, d, gold_mult))
		d += 1
		blocks += 1
		hp = block_hp(bal, d)
	if blocks < max_blocks:
		hp = hp.sub(remaining)
	return {"depth": d, "hp": hp, "gold": gold, "blocks": blocks}
