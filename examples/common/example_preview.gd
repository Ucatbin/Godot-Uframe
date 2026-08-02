extends Control

## 启动器卡片内的原生动态预览。只画最小玩法轮廓，不创建子节点或素材。

var kind := &"arena"
var accent := Color("#5ca8ff")
var _time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## 设置预览类型：arena、platformer、inventory 或 spider。
func configure(preview_kind: StringName, color: Color) -> void:
	kind = preview_kind
	accent = color
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Color("#08101a"), 0.46), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(accent, 0.22), false, 1.0)
	match kind:
		&"arena": _draw_arena()
		&"platformer": _draw_platformer()
		&"spider": _draw_spider()
		_: _draw_inventory()

func _draw_arena() -> void:
	var center := size * 0.5
	draw_arc(center, 26.0, 0, TAU, 28, Color(accent, 0.22), 1.0)
	draw_circle(center, 8.0, Color("#5ca8ff"))
	for index in 3:
		var angle := _time * (0.55 + index * 0.12) + index * TAU / 3.0
		var enemy := center + Vector2(cos(angle), sin(angle)) * (27.0 + index * 5.0)
		draw_circle(enemy, 5.0, accent)
	var shot_direction := Vector2(cos(_time * 2.0), sin(_time * 2.0))
	draw_line(center + shot_direction * 10.0, center + shot_direction * 24.0, Color("#ffca70"), 3.0)

func _draw_platformer() -> void:
	var floor_y := size.y - 14.0
	draw_line(Vector2(10, floor_y), Vector2(size.x - 10, floor_y), Color(accent, 0.55), 5.0)
	draw_line(Vector2(size.x * 0.43, floor_y - 23), Vector2(size.x * 0.67, floor_y - 23), Color(accent, 0.42), 5.0)
	draw_line(Vector2(size.x * 0.70, floor_y - 45), Vector2(size.x - 12, floor_y - 45), Color("#66d9a0", 0.58), 5.0)
	var jump := absf(sin(_time * 1.65))
	var player_position := Vector2(22.0 + jump * (size.x - 54.0), floor_y - 8.0 - sin(jump * PI) * 30.0)
	draw_rect(Rect2(player_position - Vector2(4, 8), Vector2(8, 12)), Color("#ffca70"), true)

func _draw_inventory() -> void:
	var cell := 13.0
	var gap := 4.0
	var origin := (size - Vector2(cell * 6 + gap * 5, cell * 3 + gap * 2)) * 0.5
	for y in 3:
		for x in 6:
			var rect := Rect2(origin + Vector2(x, y) * (cell + gap), Vector2.ONE * cell)
			draw_rect(rect, Color("#111b28"), true)
			draw_rect(rect, Color(accent, 0.24), false, 1.0)
	for index in 5:
		var x := (index + int(_time * 0.7)) % 6
		var y := index % 3
		draw_circle(origin + Vector2(x, y) * (cell + gap) + Vector2.ONE * cell * 0.5, 4.0, accent.lightened(index * 0.05))

func _draw_spider() -> void:
	# 淡色蛛网负责营造主题，牌面仍保持高对比和清晰轮廓。
	var web_center := size * Vector2(0.5, 0.54)
	for radius in [18.0, 32.0, 46.0]:
		draw_arc(web_center, radius, 0.0, TAU, 32, Color(accent, 0.055), 1.0)
	for index in 8:
		var direction := Vector2.from_angle(index * TAU / 8.0)
		draw_line(web_center, web_center + direction * 52.0, Color(accent, 0.045), 1.0)

	var card_size := Vector2(15.0, 21.0)
	var column_step := (size.x - 28.0 - card_size.x) / 9.0
	var origin := Vector2(14.0, 13.0)
	for column in 10:
		var card_count := 2 + column % 4
		for row in card_count:
			var card_position := origin + Vector2(column * column_step, row * 6.0)
			var face_up := row == card_count - 1
			# 预览轮换四种花色，让启动器卡片也能直接表达三档难度的核心差异。
			_draw_spider_card(Rect2(card_position, card_size), face_up, Color.TRANSPARENT, column % 4)

	# 一张牌在两列之间往返，表现拖拽时的弧线和琥珀落点提示。
	var cycle := fmod(_time * 0.55, 2.0)
	var progress := cycle if cycle <= 1.0 else 2.0 - cycle
	var eased := progress * progress * (3.0 - 2.0 * progress)
	var source := origin + Vector2(column_step * 2.0, 34.0)
	var target := origin + Vector2(column_step * 7.0, 28.0)
	var moving_position := source.lerp(target, eased) - Vector2(0.0, sin(progress * PI) * 15.0)
	draw_circle(target + card_size * 0.5, 12.0 + sin(_time * 3.0) * 1.5, Color("#ffc857", 0.08))
	_draw_spider_card(Rect2(moving_position, card_size), true, Color("#ffc857"), 3)

func _draw_spider_card(rect: Rect2, face_up: bool, border := Color.TRANSPARENT, suit := 0) -> void:
	draw_rect(Rect2(rect.position + Vector2(1.5, 2.0), rect.size), Color("#000000", 0.22), true)
	var fill := Color("#f4e6c5") if face_up else Color("#12352f")
	var outline := border if border.a > 0.0 else Color(accent, 0.72 if face_up else 0.34)
	draw_rect(rect, fill, true)
	draw_rect(rect, outline, false, 1.0)
	if face_up:
		_draw_spider_suit(rect.position + Vector2(5.0, 5.5), suit)
		draw_line(rect.position + Vector2(3.0, 10.0), rect.position + Vector2(11.0, 10.0), Color("#19312f", 0.34), 1.0)
	else:
		draw_line(rect.position + Vector2(3.0, 4.0), rect.end - Vector2(3.0, 4.0), Color(accent, 0.24), 1.0)
		draw_line(Vector2(rect.end.x - 3.0, rect.position.y + 4.0), Vector2(rect.position.x + 3.0, rect.end.y - 4.0), Color(accent, 0.24), 1.0)


## 卡片只有 15×21 像素，使用原生图元代替字体，避免预览依赖额外素材或字号。
func _draw_spider_suit(center: Vector2, suit: int) -> void:
	match clampi(suit, 0, 3):
		0: # 黑桃
			var color := Color("#244d42")
			draw_circle(center + Vector2(-1.1, 0.0), 1.6, color)
			draw_circle(center + Vector2(1.1, 0.0), 1.6, color)
			draw_colored_polygon(PackedVector2Array([center + Vector2(-2.6, 0.2), center + Vector2(0.0, -3.0), center + Vector2(2.6, 0.2)]), color)
			draw_line(center + Vector2(0.0, 1.0), center + Vector2(0.0, 3.0), color, 1.0)
		1: # 红桃
			var color := Color("#b83b5e")
			draw_circle(center + Vector2(-1.1, -0.8), 1.5, color)
			draw_circle(center + Vector2(1.1, -0.8), 1.5, color)
			draw_colored_polygon(PackedVector2Array([center + Vector2(-2.5, -0.5), center + Vector2(2.5, -0.5), center + Vector2(0.0, 3.0)]), color)
		2: # 梅花
			var color := Color("#6653a6")
			draw_circle(center + Vector2(0.0, -1.5), 1.5, color)
			draw_circle(center + Vector2(-1.5, 0.4), 1.5, color)
			draw_circle(center + Vector2(1.5, 0.4), 1.5, color)
			draw_line(center + Vector2(0.0, 1.0), center + Vector2(0.0, 3.0), color, 1.0)
		_: # 方片
			var color := Color("#c8782e")
			draw_colored_polygon(PackedVector2Array([center + Vector2(0.0, -3.0), center + Vector2(2.4, 0.0), center + Vector2(0.0, 3.0), center + Vector2(-2.4, 0.0)]), color)
