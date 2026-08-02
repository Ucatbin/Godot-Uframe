class_name SpiderCardView
extends Control

## 蜘蛛纸牌的轻量卡牌 View。
##
## 这是一个只有根 Control 的程序化绘制场景：没有图片资源，也没有常驻 _process()。
## 规则模型只需调用 configure() 同步牌面数据；合法移动、收组等规则不放在 View 中。
## 悬停、翻牌、闪光和庆祝均由短时 Tween 驱动，动画结束后不会继续产生逐帧开销。

## 按下卡牌时发出。Board 可以由 card.card_id 找到规则模型中的同一张牌。
signal pressed(card: SpiderCardView)
## 右键牌面时发出。Board 会为这张牌及其上方合法牌组寻找最佳目标列。
signal auto_move_requested(card: SpiderCardView)

const CARD_SIZE := Vector2(76.0, 106.0)
const CARD_MARGIN := 2.0
const CORNER_RADIUS := 9.0

const IVORY := Color("#f6edcf")
const IVORY_LIGHT := Color("#fff8e4")
const IVORY_DARK := Color("#d8c594")
const FACE_INK := Color("#8f3742")
const FACE_GREEN := Color("#244d42")
const HEART_RED := Color("#b83b5e")
const CLUB_PURPLE := Color("#6653a6")
const DIAMOND_ORANGE := Color("#c8782e")
const BACK_GREEN := Color("#123e34")
const BACK_GREEN_LIGHT := Color("#1c5948")
const WEB_COLOR := Color("#a9c9ac")
const GOLD := Color("#f2c66d")
const FOCUS_BLUE := Color("#72b8e8")

## 规则模型中的唯一牌 ID。-1 表示尚未配置。
var card_id := -1
## 1=A、11=J、12=Q、13=K。
var rank := 1
## 0/1/2/3 分别显示为 ♠/♥/♣/♦。规则仍由 SpiderGameModel 判断。
var suit := 0
## true 绘制暖象牙牌面，false 绘制墨绿蛛网牌背。
var face_up := false

## false 时忽略鼠标和键盘输入，但仍正常绘制。
@export var interactive := true:
	set(value):
		# 控制器会在同步牌局时重复写入相同状态。没有这个短路，暗牌会为一次
		# “false → false”创建悬停 Tween，并在数帧内无意义地重绘整张牌。
		if interactive == value:
			return
		interactive = value
		_sync_interaction()

var _hovered := false
var _dragging := false

## 下列属性仅在短时 Tween 运行期间变化；Setter 负责按需重绘。
var _hover_amount := 0.0:
	set(value):
		_hover_amount = clampf(value, 0.0, 1.0)
		queue_redraw()

var _flash_alpha := 0.0:
	set(value):
		_flash_alpha = clampf(value, 0.0, 1.0)
		queue_redraw()

var _pulse_amount := 0.0:
	set(value):
		_pulse_amount = clampf(value, 0.0, 1.0)
		queue_redraw()

var _celebration_amount := 0.0:
	set(value):
		_celebration_amount = clampf(value, 0.0, 1.0)
		queue_redraw()

## 当前卡牌真正露出的高度。被下一张牌覆盖时只绘制顶部条，避免为不可见区域
## 提交中央花色、底角、完整蛛网等几十条 Canvas 绘制命令。
var _exposed_height := CARD_SIZE.y

var _flash_color := GOLD
var _font: Font
var _hover_tween: Tween
var _move_tween: Tween
var _flip_tween: Tween
var _flash_tween: Tween
var _celebration_tween: Tween


func _ready() -> void:
	_font = ThemeDB.fallback_font
	pivot_offset = size * 0.5
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_on_resized)
	_sync_interaction()
	_update_tooltip()
	queue_redraw()


## 用规则模型中的数据刷新这张牌。第四个参数有默认值，旧的单色调用仍然兼容。
## 配置只同步显示数据，不会自行判断规则或播放翻牌动画。
func configure(new_card_id: int, new_rank: int, new_face_up: bool, new_suit := 0) -> void:
	card_id = new_card_id
	rank = clampi(new_rank, 1, 13)
	suit = clampi(new_suit, 0, 3)
	face_up = new_face_up
	_update_tooltip()
	queue_redraw()


## Board 根据相邻卡牌间距写入露出高度；相同值不会触发重绘。
func set_exposed_height(value: float) -> void:
	var resolved := clampf(value, 8.0, CARD_SIZE.y)
	if is_equal_approx(_exposed_height, resolved):
		return
	_exposed_height = resolved
	queue_redraw()


## 设置正反面。animated=false 适合初始化或撤销后的整盘快速刷新。
func set_face_up(value: bool, animated := true, duration := 0.18) -> void:
	if value == face_up:
		return
	_kill_tween(_flip_tween)
	if not animated or not is_inside_tree() or duration <= 0.0:
		face_up = value
		# 翻牌使用节点变换而非逐帧重建自定义绘制；立即同步时恢复等比缩放。
		scale.x = scale.y
		_update_tooltip()
		queue_redraw()
		return

	var half_duration := maxf(duration * 0.5, 0.01)
	var full_scale_x := maxf(absf(scale.y), 0.001)
	_flip_tween = create_tween()
	_flip_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# scale 是 CanvasItem 变换，渲染服务器可以复用已有绘制命令；旧实现 Tween
	# 自定义属性并每帧 queue_redraw()，十张同时翻开时会重建十份复杂几何。
	_flip_tween.tween_property(self, "scale:x", full_scale_x * 0.03, half_duration)
	_flip_tween.tween_callback(_apply_face_up.bind(value))
	_flip_tween.set_ease(Tween.EASE_OUT)
	_flip_tween.tween_property(self, "scale:x", full_scale_x, half_duration)


## Board 在拖动一张或一组牌时调用。这里只改变表现，不自行修改位置或游戏规则。
func set_dragging(value: bool) -> void:
	if _dragging == value:
		return
	_dragging = value
	mouse_default_cursor_shape = Control.CURSOR_DRAG if value else Control.CURSOR_POINTING_HAND
	_animate_hover()
	queue_redraw()


func is_dragging() -> bool:
	return _dragging


func is_hovered() -> bool:
	return _hovered


## 平滑移动到父节点坐标中的目标位置。duration=0 时立即就位。
func move_to(target_position: Vector2, duration := 0.18, delay := 0.0) -> Tween:
	_kill_tween(_move_tween)
	# 同步 HUD 或无关列时，位置通常没有变化；跳过 Tween 可避免一次动作创建几十个空动画。
	if delay <= 0.0 and position.distance_squared_to(target_position) <= 0.01:
		position = target_position
		return null
	if not is_inside_tree() or duration <= 0.0:
		position = target_position
		return null
	_move_tween = create_tween()
	if delay > 0.0:
		_move_tween.tween_interval(delay)
	_move_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(self, "position", target_position, duration)
	return _move_tween


## 播放一次短闪光，例如合法落牌或提示可移动牌组。
func flash(color := GOLD, duration := 0.36) -> void:
	_flash_color = color
	_flash_alpha = 1.0
	_pulse_amount = 1.0
	_kill_tween(_flash_tween)
	if not is_inside_tree():
		_flash_alpha = 0.0
		_pulse_amount = 0.0
		return
	_flash_tween = create_tween().set_parallel()
	_flash_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(self, "_flash_alpha", 0.0, maxf(duration, 0.01))
	_flash_tween.tween_property(self, "_pulse_amount", 0.0, maxf(duration * 0.75, 0.01))


## 收齐 K 到 A 时播放庆祝光芒。delay 可用于让 13 张牌依次亮起。
func celebrate(delay := 0.0) -> void:
	_kill_tween(_celebration_tween)
	_celebration_amount = 0.0
	if not is_inside_tree():
		return
	_celebration_tween = create_tween()
	if delay > 0.0:
		_celebration_tween.tween_interval(delay)
	_celebration_tween.tween_callback(_begin_celebration)
	_celebration_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_celebration_tween.tween_property(self, "_celebration_amount", 1.0, 0.16)
	_celebration_tween.set_trans(Tween.TRANS_QUAD)
	_celebration_tween.tween_property(self, "_celebration_amount", 0.0, 0.52)


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	var mouse_button := event as InputEventMouseButton
	if mouse_button == null or not mouse_button.pressed:
		return
	if mouse_button.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		pressed.emit(self)
		accept_event()
		return
	if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
		grab_focus()
		auto_move_requested.emit(self)
		accept_event()
		return
	# 本示例用“按住并拖动”表达移动，键盘按键继续向场景控制器传播。
	# 因此卡牌获得焦点后，Space 仍然可以执行全局发牌，不会误进入无释放事件的拖拽。


func _draw() -> void:
	var draw_size := size
	if draw_size.x <= 0.0 or draw_size.y <= 0.0:
		draw_size = CARD_SIZE
	var center := draw_size * 0.5
	var lift := 4.0 if _dragging else _hover_amount * 2.0
	var visual_scale := 1.0 + _hover_amount * 0.018 + _pulse_amount * 0.035
	draw_set_transform(center + Vector2(0.0, -lift), 0.0, Vector2.ONE * visual_scale)
	var card_rect := Rect2(-draw_size * 0.5 + Vector2.ONE * CARD_MARGIN, draw_size - Vector2.ONE * CARD_MARGIN * 2.0)
	var compact := _exposed_height < draw_size.y - CARD_MARGIN * 2.0
	var visible_rect := card_rect
	if compact:
		visible_rect.size.y = clampf(_exposed_height - CARD_MARGIN, 8.0, card_rect.size.y)

	var shadow_alpha := 0.24 + _hover_amount * 0.08 + (0.09 if _dragging else 0.0)
	var shadow_rect := Rect2(visible_rect.position + Vector2(0.0, 3.0 + lift * 0.35), visible_rect.size)
	_draw_rounded_rect(shadow_rect, Color(0.01, 0.03, 0.025, shadow_alpha), CORNER_RADIUS)
	if compact:
		_draw_compact_card(visible_rect)
	elif face_up:
		_draw_face(card_rect)
	else:
		_draw_back(card_rect)

	if has_focus() or _hovered or _dragging:
		var outline_color := GOLD if _dragging else (FOCUS_BLUE if has_focus() else IVORY_LIGHT)
		_draw_rounded_outline(visible_rect.grow(-1.0), outline_color, CORNER_RADIUS - 1.0, 1.5)
	if _flash_alpha > 0.0:
		var glow := _flash_color
		glow.a = _flash_alpha
		_draw_rounded_outline(visible_rect.grow(1.5), glow, CORNER_RADIUS + 1.5, 2.5)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _celebration_amount > 0.0:
		_draw_celebration(center + Vector2(0.0, -lift), draw_size)


## 被覆盖的卡牌只需要顶部轮廓和角标。尤其牌背不再绘制 3 个 32 段圆环，
## 长牌列的常驻 Canvas 命令量会显著降低。
func _draw_compact_card(card_rect: Rect2) -> void:
	_draw_rounded_rect(card_rect, IVORY_DARK, minf(CORNER_RADIUS, card_rect.size.y * 0.45))
	var inner := card_rect.grow(-2.0)
	if inner.size.y <= 0.0:
		return
	if face_up:
		_draw_rounded_rect(inner, IVORY.lightened(_hover_amount * 0.035), minf(CORNER_RADIUS - 2.0, inner.size.y * 0.42))
		var baseline := inner.position + Vector2(5.0, clampf(inner.size.y - 1.5, 8.0, 20.0))
		draw_string(_font, baseline, "%s%s" % [_rank_text(), _suit_glyph()], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, _suit_color())
	else:
		_draw_rounded_rect(inner, BACK_GREEN_LIGHT, minf(CORNER_RADIUS - 2.0, inner.size.y * 0.42))
		var y := inner.position.y + inner.size.y * 0.5
		draw_line(Vector2(inner.position.x + 5.0, y), Vector2(inner.end.x - 5.0, y), Color(WEB_COLOR, 0.52), 1.0)
		_draw_rounded_outline(inner.grow(-1.0), Color(WEB_COLOR, 0.38), minf(CORNER_RADIUS - 3.0, inner.size.y * 0.38), 1.0)


func _draw_face(card_rect: Rect2) -> void:
	_draw_rounded_rect(card_rect, IVORY_DARK, CORNER_RADIUS)
	var inner := card_rect.grow(-2.0)
	var fill := IVORY.lightened(_hover_amount * 0.035)
	_draw_rounded_rect(inner, fill, CORNER_RADIUS - 2.0)
	var suit_color := _suit_color()
	_draw_rounded_outline(inner.grow(-2.0), Color(suit_color, 0.20), CORNER_RADIUS - 4.0, 1.0)

	var rank_text := _rank_text()
	var corner_text := "%s%s" % [rank_text, _suit_glyph()]
	# 叠牌时通常只露出顶部约 26px，所以点数和花色必须在同一行出现。
	draw_string(_font, inner.position + Vector2(5.0, 22.0), corner_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, suit_color)
	var bottom_width := 42.0
	draw_string(
		_font,
		Vector2(inner.end.x - bottom_width - 5.0, inner.end.y - 7.0),
		corner_text,
		HORIZONTAL_ALIGNMENT_RIGHT,
		bottom_width,
		16,
		suit_color
	)

	# 大花色负责快速识别；淡蜘蛛水印保留本示例自己的午夜蛛网主题。
	draw_string(
		_font,
		Vector2(inner.position.x + 5.0, card_rect.get_center().y + 10.0),
		_suit_glyph(),
		HORIZONTAL_ALIGNMENT_CENTER,
		inner.size.x - 10.0,
		30,
		suit_color
	)
	_draw_spider(card_rect.get_center() + Vector2(0.0, 25.0), Color(suit_color, 0.24), 0.48)


func _draw_back(card_rect: Rect2) -> void:
	_draw_rounded_rect(card_rect, IVORY_DARK, CORNER_RADIUS)
	var inner := card_rect.grow(-2.0)
	var fill := BACK_GREEN_LIGHT.lightened(_hover_amount * 0.035)
	_draw_rounded_rect(inner, fill, CORNER_RADIUS - 2.0)
	var web_rect := inner.grow(-5.0)
	_draw_rounded_outline(web_rect, Color(WEB_COLOR, 0.62), CORNER_RADIUS - 5.0, 1.0)

	var web_center := web_rect.get_center()
	var radius := minf(web_rect.size.x, web_rect.size.y) * 0.42
	for index in 8:
		var direction := Vector2.from_angle(TAU * float(index) / 8.0)
		draw_line(web_center, web_center + direction * radius, Color(WEB_COLOR, 0.56), 1.0, true)
	for ring in [0.32, 0.58, 0.84]:
		draw_arc(web_center, radius * ring, 0.0, TAU, 32, Color(WEB_COLOR, 0.58), 1.0, true)
	_draw_spider(web_center, IVORY_LIGHT, 0.48)


func _draw_spider(center: Vector2, color: Color, scale_factor: float) -> void:
	var body_radius := 5.2 * scale_factor
	var head_radius := 3.2 * scale_factor
	for side in [-1.0, 1.0]:
		for index in 4:
			var y_offset := (-5.0 + index * 3.4) * scale_factor
			var hip := center + Vector2(side * 3.5, y_offset * 0.45)
			var knee := center + Vector2(side * (8.0 + index * 0.8), y_offset)
			var foot := center + Vector2(side * (11.5 + index * 0.9), y_offset + (index - 1.5) * 1.5 * scale_factor)
			draw_polyline(PackedVector2Array([hip, knee, foot]), color, maxf(1.0, 1.4 * scale_factor), true)
	draw_circle(center + Vector2(0.0, 3.0 * scale_factor), body_radius, color)
	draw_circle(center - Vector2(0.0, 4.6 * scale_factor), head_radius, color)


func _draw_celebration(center: Vector2, draw_size: Vector2) -> void:
	var strength := sin(_celebration_amount * PI)
	var base_radius := minf(draw_size.x, draw_size.y) * (0.48 + _celebration_amount * 0.12)
	var color := _suit_color().lerp(GOLD, 0.34)
	color.a = 0.9 * strength
	for index in 10:
		var angle := TAU * float(index) / 10.0 + card_id * 0.17
		var direction := Vector2.from_angle(angle)
		var origin := center + direction * base_radius
		var length := (4.0 + float(index % 3) * 2.0) * strength
		draw_line(origin - direction * length, origin + direction * length, color, 1.8, true)
		draw_circle(origin, 1.4 + strength, color)


func _draw_rounded_rect(rect: Rect2, color: Color, radius: float) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var resolved_radius := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	draw_rect(Rect2(rect.position + Vector2(resolved_radius, 0.0), Vector2(rect.size.x - resolved_radius * 2.0, rect.size.y)), color)
	draw_rect(Rect2(rect.position + Vector2(0.0, resolved_radius), Vector2(rect.size.x, rect.size.y - resolved_radius * 2.0)), color)
	draw_circle(rect.position + Vector2(resolved_radius, resolved_radius), resolved_radius, color)
	draw_circle(Vector2(rect.end.x - resolved_radius, rect.position.y + resolved_radius), resolved_radius, color)
	draw_circle(Vector2(rect.position.x + resolved_radius, rect.end.y - resolved_radius), resolved_radius, color)
	draw_circle(rect.end - Vector2(resolved_radius, resolved_radius), resolved_radius, color)


func _draw_rounded_outline(rect: Rect2, color: Color, radius: float, width: float) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var resolved_radius := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var left := rect.position.x
	var top := rect.position.y
	var right := rect.end.x
	var bottom := rect.end.y
	draw_line(Vector2(left + resolved_radius, top), Vector2(right - resolved_radius, top), color, width, true)
	draw_line(Vector2(left + resolved_radius, bottom), Vector2(right - resolved_radius, bottom), color, width, true)
	draw_line(Vector2(left, top + resolved_radius), Vector2(left, bottom - resolved_radius), color, width, true)
	draw_line(Vector2(right, top + resolved_radius), Vector2(right, bottom - resolved_radius), color, width, true)
	draw_arc(Vector2(left + resolved_radius, top + resolved_radius), resolved_radius, PI, PI * 1.5, 8, color, width, true)
	draw_arc(Vector2(right - resolved_radius, top + resolved_radius), resolved_radius, PI * 1.5, TAU, 8, color, width, true)
	draw_arc(Vector2(right - resolved_radius, bottom - resolved_radius), resolved_radius, 0.0, PI * 0.5, 8, color, width, true)
	draw_arc(Vector2(left + resolved_radius, bottom - resolved_radius), resolved_radius, PI * 0.5, PI, 8, color, width, true)


func _rank_text() -> String:
	match rank:
		1: return "A"
		11: return "J"
		12: return "Q"
		13: return "K"
		_: return str(rank)


func _suit_glyph() -> String:
	match suit:
		1: return "♥"
		2: return "♣"
		3: return "♦"
		_: return "♠"


func _suit_name() -> String:
	match suit:
		1: return "红心"
		2: return "梅花"
		3: return "方块"
		_: return "黑桃"


func _suit_color() -> Color:
	match suit:
		1: return HEART_RED
		2: return CLUB_PURPLE
		3: return DIAMOND_ORANGE
		_: return FACE_GREEN


func _apply_face_up(value: bool) -> void:
	face_up = value
	_update_tooltip()
	queue_redraw()


func _begin_celebration() -> void:
	flash(GOLD, 0.46)


func _on_mouse_entered() -> void:
	if not interactive:
		return
	_hovered = true
	_animate_hover()


func _on_mouse_exited() -> void:
	_hovered = false
	_animate_hover()


func _animate_hover() -> void:
	var target := 1.0 if (_hovered or _dragging) and interactive else 0.0
	_kill_tween(_hover_tween)
	# 停掉可能朝旧目标运动的 Tween 后，零变化不再创建新 Tween。
	if is_equal_approx(_hover_amount, target):
		return
	if not is_inside_tree():
		_hover_amount = target
		return
	_hover_tween = create_tween()
	_hover_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(self, "_hover_amount", target, 0.11)


func _on_resized() -> void:
	pivot_offset = size * 0.5
	queue_redraw()


func _sync_interaction() -> void:
	if not is_node_ready():
		return
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_CLICK if interactive else Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_DRAG if _dragging else Control.CURSOR_POINTING_HAND
	if not interactive:
		_hovered = false
		_dragging = false
		_animate_hover()


func _update_tooltip() -> void:
	if card_id < 0:
		tooltip_text = "未配置的卡牌"
	elif face_up:
		tooltip_text = "%s%s · %s · 卡牌 %d · 右键自动移动" % [_rank_text(), _suit_glyph(), _suit_name(), card_id]
	else:
		tooltip_text = "背面卡牌"


func _kill_tween(tween: Tween) -> void:
	if tween and tween.is_valid():
		tween.kill()
