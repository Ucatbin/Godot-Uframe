class_name Easing
# Easing.gd
# 缓动函数库 —— 对标 DOTween 的 Ease 枚举
# 用法：Easing.ease(Easing.Type.OUT_ELASTIC, t)
# 其中 t ∈ [0.0, 1.0]，返回值 ∈ [0.0, 1.0]
#
# 所有缓动曲线遵循 https://easings.net 标准
# 命名约定与 DOTween 保持一致

# =============================================================================
# 缓动类型枚举
# =============================================================================
enum Type {
	LINEAR,

	IN_SINE, OUT_SINE, IN_OUT_SINE,
	IN_QUAD, OUT_QUAD, IN_OUT_QUAD,
	IN_CUBIC, OUT_CUBIC, IN_OUT_CUBIC,
	IN_QUART, OUT_QUART, IN_OUT_QUART,
	IN_QUINT, OUT_QUINT, IN_OUT_QUINT,
	IN_EXPO, OUT_EXPO, IN_OUT_EXPO,
	IN_CIRC, OUT_CIRC, IN_OUT_CIRC,
	IN_ELASTIC, OUT_ELASTIC, IN_OUT_ELASTIC,
	IN_BACK, OUT_BACK, IN_OUT_BACK,
	IN_BOUNCE, OUT_BOUNCE, IN_OUT_BOUNCE,

	## DOTween 特有的 Flash 系列（快速闪烁后到达目标）
	FLASH, IN_FLASH, OUT_FLASH, IN_OUT_FLASH,
}


# =============================================================================
# 主入口：根据类型计算缓动值
# =============================================================================
static func ease(type: Type, t: float) -> float:
	match type:
		Type.LINEAR:         return _linear(t)

		Type.IN_SINE:        return _in_sine(t)
		Type.OUT_SINE:       return _out_sine(t)
		Type.IN_OUT_SINE:    return _in_out_sine(t)

		Type.IN_QUAD:        return _in_quad(t)
		Type.OUT_QUAD:       return _out_quad(t)
		Type.IN_OUT_QUAD:    return _in_out_quad(t)

		Type.IN_CUBIC:       return _in_cubic(t)
		Type.OUT_CUBIC:      return _out_cubic(t)
		Type.IN_OUT_CUBIC:   return _in_out_cubic(t)

		Type.IN_QUART:       return _in_quart(t)
		Type.OUT_QUART:      return _out_quart(t)
		Type.IN_OUT_QUART:   return _in_out_quart(t)

		Type.IN_QUINT:       return _in_quint(t)
		Type.OUT_QUINT:      return _out_quint(t)
		Type.IN_OUT_QUINT:   return _in_out_quint(t)

		Type.IN_EXPO:        return _in_expo(t)
		Type.OUT_EXPO:       return _out_expo(t)
		Type.IN_OUT_EXPO:    return _in_out_expo(t)

		Type.IN_CIRC:        return _in_circ(t)
		Type.OUT_CIRC:       return _out_circ(t)
		Type.IN_OUT_CIRC:    return _in_out_circ(t)

		Type.IN_ELASTIC:     return _in_elastic(t)
		Type.OUT_ELASTIC:    return _out_elastic(t)
		Type.IN_OUT_ELASTIC: return _in_out_elastic(t)

		Type.IN_BACK:        return _in_back(t)
		Type.OUT_BACK:       return _out_back(t)
		Type.IN_OUT_BACK:    return _in_out_back(t)

		Type.IN_BOUNCE:      return _in_bounce(t)
		Type.OUT_BOUNCE:     return _out_bounce(t)
		Type.IN_OUT_BOUNCE:  return _in_out_bounce(t)

		Type.FLASH:          return _flash(t, 0.0, 1.0)
		Type.IN_FLASH:       return _flash(t, 1.0, 0.0)
		Type.OUT_FLASH:      return _flash(t, 0.0, 1.0)
		Type.IN_OUT_FLASH:   return _in_out_flash(t)

	return t


# =============================================================================
# 便捷静态方法（可直接 Easing.out_elastic(t) 调用）
# =============================================================================

static func linear(t: float) -> float:        return _linear(t)
static func in_sine(t: float) -> float:       return _in_sine(t)
static func out_sine(t: float) -> float:      return _out_sine(t)
static func in_out_sine(t: float) -> float:   return _in_out_sine(t)
static func in_quad(t: float) -> float:       return _in_quad(t)
static func out_quad(t: float) -> float:      return _out_quad(t)
static func in_out_quad(t: float) -> float:   return _in_out_quad(t)
static func in_cubic(t: float) -> float:      return _in_cubic(t)
static func out_cubic(t: float) -> float:     return _out_cubic(t)
static func in_out_cubic(t: float) -> float:  return _in_out_cubic(t)
static func in_quart(t: float) -> float:      return _in_quart(t)
static func out_quart(t: float) -> float:     return _out_quart(t)
static func in_out_quart(t: float) -> float:  return _in_out_quart(t)
static func in_quint(t: float) -> float:      return _in_quint(t)
static func out_quint(t: float) -> float:     return _out_quint(t)
static func in_out_quint(t: float) -> float:  return _in_out_quint(t)
static func in_expo(t: float) -> float:       return _in_expo(t)
static func out_expo(t: float) -> float:      return _out_expo(t)
static func in_out_expo(t: float) -> float:   return _in_out_expo(t)
static func in_circ(t: float) -> float:       return _in_circ(t)
static func out_circ(t: float) -> float:      return _out_circ(t)
static func in_out_circ(t: float) -> float:   return _in_out_circ(t)
static func in_elastic(t: float) -> float:    return _in_elastic(t)
static func out_elastic(t: float) -> float:   return _out_elastic(t)
static func in_out_elastic(t: float) -> float: return _in_out_elastic(t)
static func in_back(t: float) -> float:       return _in_back(t)
static func out_back(t: float) -> float:      return _out_back(t)
static func in_out_back(t: float) -> float:   return _in_out_back(t)
static func in_bounce(t: float) -> float:     return _in_bounce(t)
static func out_bounce(t: float) -> float:    return _out_bounce(t)
static func in_out_bounce(t: float) -> float: return _in_out_bounce(t)
static func flash(t: float) -> float:         return _flash(t, 0.0, 1.0)


# =============================================================================
# 底层实现函数
# =============================================================================

# --- Linear ---
static func _linear(t: float) -> float:
	return t


# --- Sine ---
static func _in_sine(t: float) -> float:
	return 1.0 - cos(t * PI * 0.5)

static func _out_sine(t: float) -> float:
	return sin(t * PI * 0.5)

static func _in_out_sine(t: float) -> float:
	return -0.5 * (cos(PI * t) - 1.0)


# --- Quad ---
static func _in_quad(t: float) -> float:
	return t * t

static func _out_quad(t: float) -> float:
	return -t * (t - 2.0)

static func _in_out_quad(t: float) -> float:
	t *= 2.0
	if t < 1.0: return 0.5 * t * t
	t -= 1.0
	return -0.5 * (t * (t - 2.0) - 1.0)


# --- Cubic ---
static func _in_cubic(t: float) -> float:
	return t * t * t

static func _out_cubic(t: float) -> float:
	t -= 1.0
	return t * t * t + 1.0

static func _in_out_cubic(t: float) -> float:
	t *= 2.0
	if t < 1.0: return 0.5 * t * t * t
	t -= 2.0
	return 0.5 * (t * t * t + 2.0)


# --- Quart ---
static func _in_quart(t: float) -> float:
	return t * t * t * t

static func _out_quart(t: float) -> float:
	t -= 1.0
	return -(t * t * t * t - 1.0)

static func _in_out_quart(t: float) -> float:
	t *= 2.0
	if t < 1.0: return 0.5 * t * t * t * t
	t -= 2.0
	return -0.5 * (t * t * t * t - 2.0)


# --- Quint ---
static func _in_quint(t: float) -> float:
	return t * t * t * t * t

static func _out_quint(t: float) -> float:
	t -= 1.0
	return t * t * t * t * t + 1.0

static func _in_out_quint(t: float) -> float:
	t *= 2.0
	if t < 1.0: return 0.5 * t * t * t * t * t
	t -= 2.0
	return 0.5 * (t * t * t * t * t + 2.0)


# --- Expo ---
static func _in_expo(t: float) -> float:
	return 0.0 if t <= 0.0 else pow(2.0, 10.0 * (t - 1.0))

static func _out_expo(t: float) -> float:
	return 1.0 if t >= 1.0 else 1.0 - pow(2.0, -10.0 * t)

static func _in_out_expo(t: float) -> float:
	if t <= 0.0: return 0.0
	if t >= 1.0: return 1.0
	t *= 2.0
	if t < 1.0: return 0.5 * pow(2.0, 10.0 * (t - 1.0))
	t -= 1.0
	return 0.5 * (2.0 - pow(2.0, -10.0 * t))


# --- Circ ---
static func _in_circ(t: float) -> float:
	return -(sqrt(1.0 - t * t) - 1.0)

static func _out_circ(t: float) -> float:
	t -= 1.0
	return sqrt(1.0 - t * t)

static func _in_out_circ(t: float) -> float:
	t *= 2.0
	if t < 1.0: return -0.5 * (sqrt(1.0 - t * t) - 1.0)
	t -= 2.0
	return 0.5 * (sqrt(1.0 - t * t) + 1.0)


# --- Elastic ---
static func _in_elastic(t: float) -> float:
	if t <= 0.0: return 0.0
	if t >= 1.0: return 1.0
	t -= 1.0
	return -(pow(2.0, 10.0 * t) * sin((t - 0.075) * TAU / 0.3))

static func _out_elastic(t: float) -> float:
	if t <= 0.0: return 0.0
	if t >= 1.0: return 1.0
	return pow(2.0, -10.0 * t) * sin((t - 0.075) * TAU / 0.3) + 1.0

static func _in_out_elastic(t: float) -> float:
	if t <= 0.0: return 0.0
	if t >= 1.0: return 1.0
	t *= 2.0
	if t < 1.0:
		t -= 1.0
		return -0.5 * (pow(2.0, 10.0 * t) * sin((t - 0.1125) * TAU / 0.45))
	t -= 1.0
	return 0.5 * (pow(2.0, -10.0 * t) * sin((t - 0.1125) * TAU / 0.45)) + 1.0


# --- Back (overshoot amount = 1.70158) ---
const _BACK_C1: float = 1.70158
const _BACK_C2: float = 2.5949095  # _BACK_C1 * 2.5949095 ≈ for InOut

static func _in_back(t: float) -> float:
	var c3 := _BACK_C1 + 1.0
	return c3 * t * t * t - _BACK_C1 * t * t

static func _out_back(t: float) -> float:
	t -= 1.0
	var c3 := _BACK_C1 + 1.0
	return c3 * t * t * t + _BACK_C1 * t * t + 1.0

static func _in_out_back(t: float) -> float:
	var c2 := _BACK_C1 * 1.525
	t *= 2.0
	if t < 1.0:
		return 0.5 * (t * t * ((c2 + 1.0) * t - c2))
	t -= 2.0
	return 0.5 * (t * t * ((c2 + 1.0) * t + c2) + 2.0)


# --- Bounce ---
static func _in_bounce(t: float) -> float:
	return 1.0 - _out_bounce(1.0 - t)

static func _out_bounce(t: float) -> float:
	const n1 := 7.5625
	const d1 := 2.75

	if t < 1.0 / d1:
		return n1 * t * t
	elif t < 2.0 / d1:
		t -= 1.5 / d1
		return n1 * t * t + 0.75
	elif t < 2.5 / d1:
		t -= 2.25 / d1
		return n1 * t * t + 0.9375
	else:
		t -= 2.625 / d1
		return n1 * t * t + 0.984375

static func _in_out_bounce(t: float) -> float:
	if t < 0.5:
		return (1.0 - _out_bounce(1.0 - 2.0 * t)) * 0.5
	else:
		return (1.0 + _out_bounce(2.0 * t - 1.0)) * 0.5


# --- Flash (DOTween 特有：快速闪烁 3 次后到达目标) ---
static func _flash(t: float, from: float, to: float) -> float:
	# 在 t ∈ [0, 1] 期间闪烁 3 次
	var step := floor(t * 6.0)  # 6 个半周期 = 3 次闪烁
	var local_t := (t * 6.0) - step
	if int(step) % 2 == 0:
		return lerpf(from, to, local_t)
	else:
		return lerpf(to, from, local_t)

static func _in_out_flash(t: float) -> float:
	if t < 0.5:
		return _flash(t * 2.0, 1.0, 0.0)
	else:
		return _flash((t - 0.5) * 2.0, 0.0, 1.0)


# =============================================================================
# 扩展工具
# =============================================================================

## 在两个值之间按缓动曲线插值
static func lerp_eased(from: float, to: float, t: float, type: Type = Type.OUT_QUAD) -> float:
	return lerpf(from, to, ease(type, clampf(t, 0.0, 1.0)))

## 在两个 Vector2 之间按缓动曲线插值
static func lerp_vector2(from: Vector2, to: Vector2, t: float, type: Type = Type.OUT_QUAD) -> Vector2:
	return from.lerp(to, ease(type, clampf(t, 0.0, 1.0)))

## 在两个 Vector3 之间按缓动曲线插值
static func lerp_vector3(from: Vector3, to: Vector3, t: float, type: Type = Type.OUT_QUAD) -> Vector3:
	return from.lerp(to, ease(type, clampf(t, 0.0, 1.0)))

## 在两个 Color 之间按缓动曲线插值
static func lerp_color(from: Color, to: Color, t: float, type: Type = Type.OUT_QUAD) -> Color:
	return from.lerp(to, ease(type, clampf(t, 0.0, 1.0)))
