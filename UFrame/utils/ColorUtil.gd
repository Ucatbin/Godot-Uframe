class_name ColorUtil

# ColorUtil.gd
# 颜色工具，静态方法，直接 ColorUtil.xxx() 调用

const _HEX_CHARS := "0123456789ABCDEFabcdef"


# ==========
## Hex / 字符串转换
# ==========

## Hex 字符串 → Color，支持 #RRGGBB / #RRGGBBAA / RRGGBB
static func hex_to_color(hex: String) -> Color:
	hex = hex.strip_edges()
	if hex.begins_with("#"):
		hex = hex.substr(1)

	if hex.length() == 6:
		hex += "FF"  # 默认不透明

	if hex.length() == 8:
		var r := hex.substr(0, 2).hex_to_int() / 255.0
		var g := hex.substr(2, 2).hex_to_int() / 255.0
		var b := hex.substr(4, 2).hex_to_int() / 255.0
		var a := hex.substr(6, 2).hex_to_int() / 255.0
		return Color(r, g, b, a)

	push_error("[ColorUtil] 无效的 Hex 颜色: " + hex)
	return Color.WHITE


## Color → Hex 字符串（不含 #）
static func color_to_hex(c: Color, with_alpha: bool = false) -> String:
	var r := int(clampf(c.r, 0.0, 1.0) * 255)
	var g := int(clampf(c.g, 0.0, 1.0) * 255)
	var b := int(clampf(c.b, 0.0, 1.0) * 255)
	var s := "%02X%02X%02X" % [r, g, b]
	if with_alpha:
		var a := int(clampf(c.a, 0.0, 1.0) * 255)
		s += "%02X" % a
	return s


# ==========
## 颜色混合
# ==========

## 两个颜色混合，t=0 返回 a，t=1 返回 b
static func blend(a: Color, b: Color, t: float = 0.5) -> Color:
	t = clampf(t, 0.0, 1.0)
	return Color(
		lerp(a.r, b.r, t),
		lerp(a.g, b.g, t),
		lerp(a.b, b.b, t),
		lerp(a.a, b.a, t)
	)


## 变亮（amount > 0）或变暗（amount < 0），范围 [-1, 1]
static func adjust_brightness(c: Color, amount: float) -> Color:
	return Color(
		clampf(c.r + amount, 0.0, 1.0),
		clampf(c.g + amount, 0.0, 1.0),
		clampf(c.b + amount, 0.0, 1.0),
		c.a
	)


## 设置透明度，返回新 Color（不改变原对象）
static func with_alpha(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, clampf(alpha, 0.0, 1.0))


# ==========
## 预设色板
# ==========

## 获取 Material Design 风格的基础色板（返回 Array[Color]，长度 16）
static func material_palette() -> Array[Color]:
	return [
		Color("#F44336"),  # Red
		Color("#E91E63"),  # Pink
		Color("#9C27B0"),  # Purple
		Color("#673AB7"),  # Deep Purple
		Color("#3F51B5"),  # Indigo
		Color("#2196F3"),  # Blue
		Color("#03A9F4"),  # Light Blue
		Color("#00BCD4"),  # Cyan
		Color("#009688"),  # Teal
		Color("#4CAF50"),  # Green
		Color("#8BC34A"),  # Light Green
		Color("#CDDC39"),  # Lime
		Color("#FFEB3B"),  # Yellow
		Color("#FFC107"),  # Amber
		Color("#FF9800"),  # Orange
		Color("#FF5722"),  # Deep Orange
	]


## 随机从色板取一个颜色
static func random_palette_color() -> Color:
	var pal := material_palette()
	return pal[randi() % pal.size()]
