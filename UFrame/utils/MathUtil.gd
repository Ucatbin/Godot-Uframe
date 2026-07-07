class_name MathUtil

# MathUtil.gd
# 数学扩展工具，静态方法，直接 MathUtil.xxx() 调用
# 不需要挂载，不需要 Autoload

## 随机数
# ==========

## 随机整数 [from, to]
static func random_int(from: int, to: int) -> int:
	if from > to:
		var t = from; from = to; to = t
	return randi() % (to - from + 1) + from


## 随机浮点数 [from, to)
static func random_float(from: float, to: float) -> float:
	if from > to:
		var t = from; from = to; to = t
	return randf() * (to - from) + from


## 从数组随机取一个元素
static func random_pick(array: Array):
	if array.is_empty():
		return null
	return array[randi() % array.size()]


## 加权随机，weights 和 array 长度一致，返回下标
## 例：pick_weighted(["a","b","c"], [1,3,1]) → "b" 概率更高
static func pick_weighted(array: Array, weights: Array) -> int:
	if array.is_empty() or weights.size() != array.size():
		return -1

	var total := 0
	for w in weights:
		total += int(w)

	var r := randi() % total
	var cumulative := 0
	for i in array.size():
		cumulative += int(weights[i])
		if r < cumulative:
			return i
	return array.size() - 1


## Fisher-Yates 洗牌（原地修改数组）
static func shuffle(array: Array) -> void:
	var n := array.size()
	for i in range(n - 1, 0, -1):
		var j := randi() % (i + 1)
		var tmp = array[i]
		array[i] = array[j]
		array[j] = tmp


# ==========
## 角度 / 方向
# ==========

## 角度（度）→ 归一化到 [0, 360)
static func normalize_angle_deg(deg: float) -> float:
	deg = fmod(deg, 360.0)
	if deg < 0:
		deg += 360.0
	return deg


## 弧度归一化到 [-PI, PI)
static func normalize_angle_rad(rad: float) -> float:
	rad = fmod(rad + PI, TAU) - PI
	return rad


## 角度（度）→ 方向向量
static func angle_to_vector2(deg: float) -> Vector2:
	var rad := deg_to_rad(deg)
	return Vector2(cos(rad), sin(rad))


## 方向向量 → 角度（度），0° 指向右（Godot 标准）
static func vector2_to_angle(vec: Vector2) -> float:
	return rad_to_deg(atan2(vec.y, vec.x))


## 两个角度之间的最短差值（度），返回值 [-180, 180)
static func angle_diff_deg(from: float, to: float) -> float:
	var diff := normalize_angle_deg(to) - normalize_angle_deg(from)
	if diff > 180.0:
		diff -= 360.0
	elif diff < -180.0:
		diff += 360.0
	return diff


# ==========
## 插值
# ==========

## 线性插值，支持传入 t 在 [0,1] 之外（标准 lerp 不会 clamp）
static func lerp_unclamped(from: float, to: float, t: float) -> float:
	return from + (to - from) * t


## 平滑步进（Hermite 插值）
static func smoothstep(from: float, to: float, t: float) -> float:
	var t_clamped := clampf(t, 0.0, 1.0)
	var s := t_clamped * t_clamped * (3.0 - 2.0 * t_clamped)
	return lerp(from, to, s)


## 向量2 线性插值（GDScript 4.x 已内置，这里提供 clamp 版本）
static func lerp_vec2(from: Vector2, to: Vector2, t: float) -> Vector2:
	t = clampf(t, 0.0, 1.0)
	return from.lerp(to, t)


# ==========
## 其他
# ==========

## 判断两个浮点数是否"足够接近"（避免浮点误差）
static func is_equal_approx(a: float, b: float, epsilon: float = 0.0001) -> bool:
	return abs(a - b) < epsilon


## 将值 value 从范围 [in_min, in_max] 映射到 [out_min, out_max]
static func remap(value: float, in_min: float, in_max: float, out_min: float, out_max: float) -> float:
	if is_equal_approx(in_min, in_max):
		return out_min
	var t := (value - in_min) / (in_max - in_min)
	return lerp(out_min, out_max, t)
