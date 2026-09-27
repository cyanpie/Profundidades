class_name BigNum
extends RefCounted
## Número grande en notación científica: valor = m × 10^e, con 1 <= |m| < 10 (o m = 0).
## Los idle games superan rápido el rango de int/float, así que toda la economía usa este tipo.
## Se trata como inmutable: cada operación devuelve un BigNum nuevo.

const LOG10 := 2.302585092994046
## A partir de esta diferencia de exponentes, sumar el número menor no cambia el mayor.
const PRECISION_GAP := 17
const SUFFIXES: Array[String] = ["", "K", "M", "B", "T"]

var m: float = 0.0
var e: int = 0


func _init(mantissa: float = 0.0, exponent: int = 0) -> void:
	m = mantissa
	e = exponent
	_normalize()


static func zero() -> BigNum:
	return BigNum.new()


static func from_float(value: float) -> BigNum:
	return BigNum.new(value, 0)


## base^exponent sin desbordar. base debe ser > 0.
static func pow_f(base: float, exponent: float) -> BigNum:
	var l := exponent * log(base) / LOG10
	# Evita que 10^500 salga como 9.99999e499 por error de redondeo.
	if absf(l - roundf(l)) < 1e-9:
		l = roundf(l)
	var ex := floori(l)
	return BigNum.new(pow(10.0, l - ex), ex)


static func from_dict(d: Variant) -> BigNum:
	if d is Dictionary:
		return BigNum.new(float(d.get("m", 0.0)), int(d.get("e", 0)))
	return BigNum.zero()


func to_dict() -> Dictionary:
	return {"m": m, "e": e}


func copy() -> BigNum:
	return BigNum.new(m, e)


func is_zero() -> bool:
	return m == 0.0


func is_negative() -> bool:
	return m < 0.0


func neg() -> BigNum:
	return BigNum.new(-m, e)


func add(o: BigNum) -> BigNum:
	if o.is_zero():
		return copy()
	if is_zero():
		return o.copy()
	var diff := e - o.e
	if diff > PRECISION_GAP:
		return copy()
	if diff < -PRECISION_GAP:
		return o.copy()
	if diff >= 0:
		return BigNum.new(m + o.m * pow(10.0, -diff), e)
	return BigNum.new(m * pow(10.0, diff) + o.m, o.e)


func sub(o: BigNum) -> BigNum:
	return add(o.neg())


func mul(o: BigNum) -> BigNum:
	return BigNum.new(m * o.m, e + o.e)


func mul_f(f: float) -> BigNum:
	return BigNum.new(m * f, e)


func div(o: BigNum) -> BigNum:
	if o.is_zero():
		push_error("BigNum: división por cero")
		return BigNum.zero()
	return BigNum.new(m / o.m, e - o.e)


## -1, 0 o 1 según self sea menor, igual o mayor que o.
func cmp(o: BigNum) -> int:
	var s1 := int(signf(m))
	var s2 := int(signf(o.m))
	if s1 != s2:
		return 1 if s1 > s2 else -1
	if s1 == 0:
		return 0
	if e != o.e:
		return (1 if e > o.e else -1) * s1
	if m == o.m:
		return 0
	return 1 if m > o.m else -1


func gte(o: BigNum) -> bool:
	return cmp(o) >= 0


func gt(o: BigNum) -> bool:
	return cmp(o) > 0


func lt(o: BigNum) -> bool:
	return cmp(o) < 0


func to_float() -> float:
	return m * pow(10.0, e)


## Texto corto para la UI: 999, 1.23K, 45.6M, 789B, 1.00aa...
## Trunca en vez de redondear para no mostrar más oro del que hay.
func format() -> String:
	if is_zero():
		return "0"
	if is_negative():
		return "-" + neg().format()
	if e < 3:
		return str(floori(to_float() + 1e-9))
	var group := floori(e / 3.0)
	var scaled := m * pow(10.0, e - group * 3)
	var text: String
	if scaled < 10.0:
		text = "%.2f" % (floorf(scaled * 100.0 + 1e-6) / 100.0)
	elif scaled < 100.0:
		text = "%.1f" % (floorf(scaled * 10.0 + 1e-6) / 10.0)
	else:
		text = str(floori(scaled + 1e-6))
	return text + _suffix(group)


func _to_string() -> String:
	return "%se%d" % [m, e]


static func _suffix(group: int) -> String:
	if group < SUFFIXES.size():
		return SUFFIXES[group]
	var i := group - SUFFIXES.size()
	if i < 26 * 26:
		return char(97 + floori(i / 26.0)) + char(97 + i % 26)
	return "e%d" % (group * 3)


func _normalize() -> void:
	if m == 0.0 or is_nan(m) or is_inf(m):
		if is_nan(m) or is_inf(m):
			push_error("BigNum: valor inválido (%s)" % m)
		m = 0.0
		e = 0
		return
	var shift := floori(log(absf(m)) / LOG10)
	if shift != 0:
		m /= pow(10.0, shift)
		e += shift
	# Corrige errores de redondeo del logaritmo.
	if absf(m) >= 10.0:
		m /= 10.0
		e += 1
	elif absf(m) < 1.0:
		m *= 10.0
		e -= 1
