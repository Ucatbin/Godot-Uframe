class_name RandomUtil

# RandomUtil.gd
# 高级随机工具，静态方法，直接 RandomUtil.xxx() 调用
# 比 GDScript 内置 randi/randf 更丰富

# ==========
## 随机布尔
# ==========

## 按概率返回 true，chance 范围 [0.0, 1.0]，默认 0.5
static func chance(prob: float = 0.5) -> bool:
	return randf() < prob


## 抛硬币，true/false 各 50%
static func coin_flip() -> bool:
	return randi() % 2 == 0


# ==========
## 随机向量
# ==========

## 随机单位向量（圆内均匀分布）
static func random_unit_vector2() -> Vector2:
	var angle := randf() * TAU
	return Vector2(cos(angle), sin(angle))


## 随机向量，长度在 [0, length] 范围内（圆内均匀）
static func random_vector2_in_circle(max_length: float = 1.0) -> Vector2:
	# 用 sqrt 保证均匀分布
	var len := sqrt(randf()) * max_length
	var angle := randf() * TAU
	return Vector2(cos(angle), sin(angle)) * len


## 随机向量，在矩形范围内
static func random_vector2_in_rect(rect: Rect2) -> Vector2:
	var x := rect.position.x + randf() * rect.size.x
	var y := rect.position.y + randf() * rect.size.y
	return Vector2(x, y)


# ==========
## 随机颜色
# ==========

## 完全随机颜色（含随机 alpha）
static func random_color(alpha: bool = false) -> Color:
	return Color(randf(), randf(), randf(), randf() if alpha else 1.0)


## 随机鲜明颜色（HSV 随机色相，高饱和度/亮度）
static func random_vivid_color() -> Color:
	return Color.from_hsv(randf(), 0.8, 0.9)


# ==========
## 随机字符串
# ==========

const _HEX_CHARS := "0123456789ABCDEF"
const _ALPHA_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
const _ALNUM_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

## 随机 Hex 字符串，默认长度 8
static func random_hex(length: int = 8) -> String:
	var s := ""
	for i in length:
		s += _HEX_CHARS[randi() % 16]
	return s


## 随机字母数字字符串
static func random_alnum(length: int = 8) -> String:
	var s := ""
	for i in length:
		s += _ALNUM_CHARS[randi() % _ALNUM_CHARS.length()]
	return s


# ==========
## 种子（可复现随机）
# ==========

## 设置随机种子（用于复现随机结果，比如生成同一张地图）
static func set_seed(seed_value: int) -> void:
	seed(seed_value)


## 用指定种子执行一个回调函数，执行完后恢复原来的随机状态
## 用法：with_seed(12345, func(): return RandomUtil.random_int(1,100))
static func with_seed(seed_value: int, callback: Callable):
	var old_state := randi()  # 保存不了真实状态，GDScript 限制
	seed(seed_value)
	var result = callback.call()
	# 无法恢复，GDScript 不暴露 rand 状态接口
	# 建议：只在确定需要复现的场合用 set_seed + 手动重置
	return result
