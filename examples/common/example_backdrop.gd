extends Control

## 启动器与背包示例使用的轻量动态背景，仅用 CanvasItem 绘制。
##
## 组合位置见 example_browser.tscn 与 loot_demo.tscn 中的全屏 Backdrop。
## 本脚本不创建子节点，也不保存玩法数据。

#region 配置与状态
## 网格、光点和环境光使用的强调色。
@export var accent := Color("#5ca8ff")
## 程序化背景的累计动画时间。
var _time := 0.0
#endregion

#region 生命周期
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
#endregion

#region 公开接口
## 修改背景强调色。
func configure(color: Color) -> void:
	accent = color
	queue_redraw()
#endregion

#region 动画与绘制
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
#endregion
