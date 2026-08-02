extends Control

## 启动器与背包示例使用的轻量动态背景，仅用 CanvasItem 绘制。

@export var accent := Color("#5ca8ff")
var _time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## 修改背景强调色。
func configure(color: Color) -> void:
	accent = color
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var viewport_size := size
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color("#0a0f18"))
	var grid_color := Color(accent, 0.055)
	var drift := fmod(_time * 7.0, 48.0)
	for x in range(-48, int(viewport_size.x) + 96, 48):
		draw_line(Vector2(x + drift, 0), Vector2(x + drift, viewport_size.y), grid_color, 1.0)
	for y in range(-48, int(viewport_size.y) + 96, 48):
		draw_line(Vector2(0, y + drift * 0.35), Vector2(viewport_size.x, y + drift * 0.35), grid_color, 1.0)
	# 固定公式生成漂浮光点，不保存节点，也不产生随机状态。
	for index in 24:
		var px := fmod(index * 137.0 + _time * (5.0 + index % 3), viewport_size.x + 40.0) - 20.0
		var py := fmod(index * 83.0 + sin(_time * 0.7 + index) * 18.0, viewport_size.y + 30.0) - 15.0
		var alpha := 0.10 + 0.08 * sin(_time * 1.3 + index * 0.9)
		draw_circle(Vector2(px, py), 1.5 + index % 2, Color(accent, alpha))
	draw_circle(viewport_size * Vector2(0.82, 0.14), 155.0, Color(accent, 0.025))
	draw_circle(viewport_size * Vector2(0.12, 0.88), 210.0, Color(accent, 0.018))
