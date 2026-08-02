extends Control

## 可切换单色、双色与四色难度的蜘蛛纸牌示例控制器。
##
## 打开 spider_demo.tscn 可以直接看到固定十列、表面、拖拽层、集中式反馈层和 HUD。
## 只有数量取决于牌局状态的 Card View 才从 PackedScene 动态实例化；104 张牌的规则
## 统一保存在 SpiderGameModel 中，卡牌 View 不持有第二份玩法数据。

#region 配置与场景引用

const UI := preload("res://examples/common/example_ui.gd")
const MENU_SCENE := "res://examples/example_browser.tscn"

const TABLE_COLOR := Color("#071619")
const TABLE_RAISED := Color("#0b2422")
const MINT := Color("#74f0c1")
const GOLD := Color("#ffc857")
const DANGER := Color("#ff657a")
const CLIMAX := Color("#9a7cff")
const CARD_SIZE := SpiderCardView.CARD_SIZE

## 单张牌的 View 模板。重复实例属于运行时数量，不需要在场景中手工复制 104 次。
@export var card_scene: PackedScene
## 宿主可以在 Inspector 决定默认难度；玩家仍可在运行时用三个场景按钮切换。
@export_enum("单色:1", "双色:2", "四色:4") var default_suit_count := 1

@onready var board_stage: Control = %BoardStage
@onready var table_surface: Panel = $BoardStage/TableSurface
@onready var tableau: HBoxContainer = %Tableau
@onready var card_layer: Control = %CardLayer
@onready var drag_layer: Control = %DragLayer
@onready var feedback_overlay: SpiderFeedbackOverlay = %FeedbackOverlay

@onready var header_panel: PanelContainer = $HeaderMargin/HeaderPanel
@onready var moves_label: Label = %MovesLabel
@onready var score_label: Label = %ScoreLabel
@onready var stock_label: Label = %StockLabel
@onready var completed_label: Label = %CompletedLabel
@onready var completed_container: HBoxContainer = %Completed
@onready var difficulty_label: Label = $HeaderMargin/HeaderPanel/HeaderRow/TitleBlock/DifficultyRow/DifficultyLabel
@onready var one_suit_button: Button = %OneSuitButton
@onready var two_suit_button: Button = %TwoSuitButton
@onready var four_suit_button: Button = %FourSuitButton
@onready var deal_button: Button = %DealButton
@onready var undo_button: Button = %UndoButton
@onready var new_game_button: Button = %NewGameButton
@onready var back_button: Button = %BackButton
@onready var message_panel: PanelContainer = $MessagePanel
@onready var message_label: Label = %MessageLabel
@onready var big_feedback: Label = %BigFeedback
@onready var screen_flash: ColorRect = %ScreenFlash

var game := SpiderGameModel.new()
var _column_guides: Array[Panel] = []
var _completed_slots: Array[Panel] = []
## card_id → SpiderCardView。字典让同步和拖拽都不必扫描全部场景子节点。
var _card_views: Dictionary = {}
var _difficulty_buttons: Dictionary = {}
var _selected_suit_count := 1

var _dragged_views: Array[SpiderCardView] = []
var _drag_offsets: Array[Vector2] = []
var _drag_from_column := -1
var _drag_start_index := -1
var _drag_mouse_offset := Vector2.ZERO

var _normal_column_style: StyleBoxFlat
var _valid_column_style: StyleBoxFlat
var _invalid_column_style: StyleBoxFlat
var _hint_column_style: StyleBoxFlat
var _empty_run_style: StyleBoxFlat
var _filled_run_style: StyleBoxFlat
var _message_style: StyleBoxFlat
var _highlighted_column := -1
var _highlight_is_valid := false
var _styled_difficulty := -1
var _displayed_completed_runs := -1

var _busy := false
var _busy_serial := 0
var _hint_serial := 0
var _changing_scene := false
var _visual_time := 0.0
var _redraw_accumulator := 0.0
var _message_tween: Tween
var _score_tween: Tween
var _feedback_tween: Tween
var _flash_tween: Tween
var _board_tween: Tween
## 一次发牌或开局共用一个调度 Tween，避免为每张新牌分别创建移动、旋转和延时 Tween。
var _entry_tween: Tween

#endregion

#region 生命周期与输入


func _ready() -> void:
	_selected_suit_count = default_suit_count if default_suit_count in [1, 2, 4] else 1
	for child in tableau.get_children():
		var guide := child as Panel
		if guide:
			_column_guides.append(guide)
	for child in completed_container.get_children():
		var slot := child as Panel
		if slot:
			_completed_slots.append(slot)

	_difficulty_buttons = {
		1: one_suit_button,
		2: two_suit_button,
		4: four_suit_button,
	}
	_style_static_interface()
	one_suit_button.pressed.connect(_select_difficulty.bind(1))
	two_suit_button.pressed.connect(_select_difficulty.bind(2))
	four_suit_button.pressed.connect(_select_difficulty.bind(4))
	deal_button.pressed.connect(_on_deal_pressed)
	undo_button.pressed.connect(_on_undo_pressed)
	new_game_button.pressed.connect(_start_new_game)
	back_button.pressed.connect(_return_to_menu)
	get_viewport().size_changed.connect(_on_viewport_resized)

	big_feedback.modulate.a = 0.0
	screen_flash.color.a = 0.0
	# Container 要先完成一次布局，之后才能取得十列的准确位置。
	_start_new_game.call_deferred()


## 只有桌面背景使用一个共享更新：限制到约 20 次重绘/秒。
## 每张牌没有常驻 _process()，短动画全部交给 Tween。
func _process(delta: float) -> void:
	_visual_time = fmod(_visual_time + delta, 1000.0)
	_redraw_accumulator += delta
	if _redraw_accumulator >= 1.0 / 20.0:
		_redraw_accumulator = 0.0
		queue_redraw()


func _input(event: InputEvent) -> void:
	if _dragged_views.is_empty():
		return
	var motion := event as InputEventMouseMotion
	if motion:
		_update_drag_position()
		get_viewport().set_input_as_handled()
		return
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
		_finish_drag()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		_return_to_menu()
	elif key.ctrl_pressed and key.keycode == KEY_Z:
		_on_undo_pressed()
	elif key.keycode == KEY_R:
		_start_new_game()
	elif key.keycode == KEY_H:
		_show_hint()
	elif key.keycode == KEY_SPACE:
		_on_deal_pressed()
	elif key.keycode == KEY_1:
		_select_difficulty(1)
	elif key.keycode == KEY_2:
		_select_difficulty(2)
	elif key.keycode == KEY_4:
		_select_difficulty(4)
	else:
		return
	get_viewport().set_input_as_handled()


func _draw() -> void:
	var viewport_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color("#02080b"))
	# 少量稳定星点和双色辉光营造“午夜印刷品”层次，不创建额外节点。
	draw_circle(Vector2(viewport_size.x * 0.18, viewport_size.y * 0.18), 240.0, Color(MINT, 0.025))
	draw_circle(Vector2(viewport_size.x * 0.82, viewport_size.y * 0.34), 210.0, Color(CLIMAX, 0.022))
	for index in 28:
		var point := Vector2(float((index * 137) % 1040) - 30.0, float((index * 83) % 680) - 20.0)
		var twinkle := 0.18 + 0.08 * sin(_visual_time * 1.8 + float(index))
		draw_circle(point, 0.8 + float(index % 3) * 0.25, Color(MINT, twinkle))

	# 桌面下方的大蛛网只由几十条 Canvas 绘制命令组成。
	var web_center := Vector2(viewport_size.x * 0.52, viewport_size.y * 0.66)
	var web_radius := maxf(viewport_size.x, viewport_size.y) * 0.68
	for index in 16:
		var angle := TAU * float(index) / 16.0 + 0.05 * sin(_visual_time * 0.45)
		draw_line(web_center, web_center + Vector2.from_angle(angle) * web_radius, Color(MINT, 0.050), 1.0)
	for ring in 7:
		var radius := web_radius * float(ring + 1) / 7.0
		draw_arc(web_center, radius, 0.0, TAU, 48, Color(MINT, 0.035 + float(ring % 2) * 0.012), 1.0)

#endregion

#region 静态界面样式


func _style_static_interface() -> void:
	UI.apply_panel(header_panel, MINT, 8)
	# 消息只修改这一份 StyleBox 的边框色；每次动作不再分配新 Resource。
	_message_style = UI.panel_style(UI.SURFACE, MINT.darkened(0.28), 14, 9)
	message_panel.add_theme_stylebox_override("panel", _message_style)
	var table_style := UI.panel_style(TABLE_COLOR, MINT.darkened(0.62), 20, 0)
	table_style.shadow_color = Color(0.0, 0.0, 0.0, 0.38)
	table_style.shadow_size = 12
	table_surface.add_theme_stylebox_override("panel", table_style)

	UI.style_label($HeaderMargin/HeaderPanel/HeaderRow/TitleBlock/Title, 24, Color("#f4e6c5"))
	UI.style_label(difficulty_label, 11, UI.MUTED.lightened(0.08))
	UI.style_label(moves_label, 13, UI.MUTED)
	UI.style_label(score_label, 19, GOLD)
	UI.style_label(stock_label, 12, UI.MUTED.lightened(0.08))
	UI.style_label(completed_label, 13, MINT)
	UI.style_label(message_label, 13, Color("#d9f7e8"))
	UI.style_label(big_feedback, 36, GOLD)
	big_feedback.add_theme_color_override("font_outline_color", Color("#06120f"))
	big_feedback.add_theme_constant_override("outline_size", 9)

	UI.apply_button(deal_button, GOLD, true)
	UI.apply_button(undo_button, MINT)
	UI.apply_button(new_game_button, CLIMAX)
	UI.apply_button(back_button, UI.MUTED)
	# 禁用仍需一眼可读；只用背景和边框表达不可操作状态。
	undo_button.add_theme_color_override("font_disabled_color", UI.MUTED)
	deal_button.add_theme_color_override("font_disabled_color", UI.MUTED)

	_normal_column_style = _make_column_style(Color(MINT, 0.025), Color(MINT, 0.12), 1)
	_valid_column_style = _make_column_style(Color(MINT, 0.105), Color(MINT, 0.72), 2)
	_invalid_column_style = _make_column_style(Color(DANGER, 0.095), Color(DANGER, 0.76), 2)
	_hint_column_style = _make_column_style(Color(GOLD, 0.10), Color(GOLD, 0.72), 2)
	_empty_run_style = UI.panel_style(Color(MINT, 0.035), Color(MINT, 0.18), 5, 0)
	_empty_run_style.set_border_width_all(1)
	_filled_run_style = UI.panel_style(Color(GOLD, 0.32), GOLD, 5, 0)
	_filled_run_style.set_border_width_all(2)
	for guide in _column_guides:
		guide.add_theme_stylebox_override("panel", _normal_column_style)
	_refresh_completed_slots()
	_refresh_difficulty_buttons()


func _make_column_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(10)
	return style


func _apply_compact_difficulty_style(button: Button, accent: Color, active: bool) -> void:
	var normal_background := accent.darkened(0.55) if active else TABLE_RAISED
	var normal := UI.panel_style(normal_background, accent.darkened(0.28), 6, 4)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = accent.darkened(0.42) if active else TABLE_RAISED.lightened(0.08)
	hover.border_color = accent
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = accent.darkened(0.62)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = normal_background.darkened(0.12)
	disabled.border_color = accent.darkened(0.42)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", accent.lightened(0.24) if active else UI.MUTED)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", accent.darkened(0.04) if active else UI.MUTED.darkened(0.18))

#endregion

#region 牌局与重复 View 同步


func _select_difficulty(suit_count: int) -> void:
	if _busy or suit_count not in [1, 2, 4]:
		return
	if _selected_suit_count == suit_count and not game.columns.is_empty():
		return
	_selected_suit_count = suit_count
	_refresh_difficulty_buttons()
	_start_new_game()
	var accent := MINT if suit_count == 1 else (GOLD if suit_count == 2 else CLIMAX)
	_flash_screen(accent, 0.10)


func _refresh_difficulty_buttons() -> void:
	if _difficulty_buttons.is_empty():
		return
	# 四套 StyleBox 只在初始化或真正切换难度时创建。普通 HUD 刷新只改 disabled，
	# 避免一次动作的锁定/解锁重复分配 36 个主题 Resource。
	if _styled_difficulty != _selected_suit_count:
		for suit_count in [1, 2, 4]:
			var styled_button := _difficulty_buttons[suit_count] as Button
			var styled_accent := MINT if suit_count == 1 else (GOLD if suit_count == 2 else CLIMAX)
			_apply_compact_difficulty_style(styled_button, styled_accent, suit_count == _selected_suit_count)
		_styled_difficulty = _selected_suit_count
	for suit_count in [1, 2, 4]:
		var button := _difficulty_buttons[suit_count] as Button
		button.disabled = _busy


func _difficulty_name(suit_count := _selected_suit_count) -> String:
	match suit_count:
		2: return "双色"
		4: return "四色"
		_: return "单色"


func _difficulty_hint() -> String:
	if _selected_suit_count == 1:
		return "单色：拖拽或右键自动移动降序牌组 · 空列可放任意牌 · H 显示提示"
	return "%s：右键优先同花色目标 · 整组拖动与 K→A 收组必须同花色" % _difficulty_name()


func _start_new_game() -> void:
	if _changing_scene:
		return
	_cancel_drag()
	_busy_serial += 1
	if _entry_tween and _entry_tween.is_valid():
		_entry_tween.kill()
	for child in card_layer.get_children():
		child.queue_free()
	for child in drag_layer.get_children():
		child.queue_free()
	_card_views.clear()
	game.new_game(int(Time.get_ticks_usec()), _selected_suit_count)
	_sync_board([], true, 0.34)
	_lock_actions(0.72)
	_show_message(_difficulty_hint(), 4.2, MINT if _selected_suit_count == 1 else (GOLD if _selected_suit_count == 2 else CLIMAX))
	_show_big_feedback("%s蛛网已展开" % _difficulty_name(), MINT if _selected_suit_count == 1 else (GOLD if _selected_suit_count == 2 else CLIMAX), 0.72)


## 用模型状态增量同步 Card View；不会重建十列或其他固定 UI。
func _sync_board(created_ids: Array = [], stagger_created := false, duration := 0.18, changed_columns: Array = []) -> void:
	if card_scene == null:
		push_error("[SpiderDemo] 请在 SpiderDemo 根节点配置 Card Scene")
		return
	var present_ids: Dictionary = {}
	var created_order: Dictionary = {}
	for index in created_ids.size():
		created_order[int(created_ids[index])] = index

	for column in game.columns:
		for card_value in column:
			var card := card_value as Dictionary
			var card_id := int(card.get("id", -1))
			present_ids[card_id] = true
			var view := _card_views.get(card_id) as SpiderCardView
			if view == null:
				view = _create_card_view(card, stagger_created)
				if view == null:
					continue
				if not created_order.has(card_id):
					created_order[card_id] = created_order.size()
			else:
				view.set_face_up(bool(card.get("face_up", false)), true)

	var stale_ids: Array = []
	for card_id in _card_views.keys():
		if not present_ids.has(card_id):
			var stale_view := _card_views[card_id] as SpiderCardView
			if is_instance_valid(stale_view):
				stale_view.queue_free()
			stale_ids.append(card_id)
	for card_id in stale_ids:
		_card_views.erase(card_id)

	if changed_columns.is_empty():
		_layout_all_cards(duration, created_order if stagger_created else {})
	else:
		_layout_columns(changed_columns, duration, created_order if stagger_created else {})
	_refresh_hud()


func _create_card_view(card: Dictionary, animate_entry := false) -> SpiderCardView:
	var instance := card_scene.instantiate()
	var view := instance as SpiderCardView
	if view == null:
		if instance:
			instance.free()
		push_error("[SpiderDemo] Card Scene 的根节点必须使用 SpiderCardView")
		return null
	var card_id := int(card.get("id", -1))
	view.name = "Card_%03d" % card_id
	card_layer.add_child(view)
	view.size = CARD_SIZE
	# 飞行阶段统一显示牌背；到达牌列后再翻开，避免正面牌穿过 HUD 的视觉穿模感。
	var displayed_face_up := bool(card.get("face_up", false)) and not animate_entry
	view.configure(card_id, int(card.get("rank", 1)), displayed_face_up, int(card.get("suit", 0)))
	view.position = _stock_origin_in(card_layer)
	# 翻牌现在使用根节点 scale.x；入场不再同时 Tween scale，避免两种变换争用。
	view.scale = Vector2.ONE
	view.rotation = deg_to_rad(float((card_id * 7) % 9 - 4)) if animate_entry else 0.0
	view.pressed.connect(_on_card_pressed)
	view.auto_move_requested.connect(_on_card_auto_move_requested)
	_card_views[card_id] = view
	return view


func _layout_all_cards(duration := 0.18, created_order: Dictionary = {}) -> void:
	var all_columns: Array[int] = []
	for column_index in game.columns.size():
		all_columns.append(column_index)
	_layout_columns(all_columns, duration, created_order)


## 只有来源列和目标列会因一次合法拖牌改变；增量布局避免扫描并写回整副牌。
## 发牌、新局和撤销仍调用 _layout_all_cards()，因为它们可能同时影响十列。
func _layout_columns(column_indices: Array, duration := 0.18, created_order: Dictionary = {}) -> void:
	var visited: Dictionary = {}
	if not created_order.is_empty():
		if _entry_tween and _entry_tween.is_valid():
			_entry_tween.kill()
		_entry_tween = create_tween().set_parallel(true)
		_entry_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	for column_value in column_indices:
		var column_index := int(column_value)
		if column_index < 0 or column_index >= game.columns.size() or visited.has(column_index):
			continue
		visited[column_index] = true
		var column := game.columns[column_index]
		var positions := _column_card_positions(column_index)
		for card_index in column.size():
			var card := column[card_index] as Dictionary
			var card_id := int(card.get("id", -1))
			var view := _card_views.get(card_id) as SpiderCardView
			if not is_instance_valid(view):
				continue
			if view.get_parent() != card_layer:
				view.reparent(card_layer, true)
			view.z_index = card_index
			view.interactive = bool(card.get("face_up", false))
			var exposed_height := CARD_SIZE.y
			if card_index + 1 < positions.size():
				exposed_height = positions[card_index + 1].y - positions[card_index].y
			view.set_exposed_height(exposed_height)
			var delay := 0.0
			if created_order.has(card_id):
				delay = float(created_order[card_id]) * (0.006 if created_order.size() > 20 else 0.025)
			if created_order.has(card_id) and _entry_tween:
				_entry_tween.tween_property(view, "position", positions[card_index], duration).set_delay(delay)
				_entry_tween.tween_property(view, "rotation", 0.0, minf(duration + 0.08, 0.42)).set_delay(delay)
				if bool(card.get("face_up", false)):
					_entry_tween.tween_callback(view.set_face_up.bind(true, true, 0.18)).set_delay(delay + duration * 0.62)
			else:
				view.move_to(positions[card_index], duration, delay)


func _column_card_positions(column_index: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if column_index < 0 or column_index >= _column_guides.size():
		return result
	var guide := _column_guides[column_index]
	var column := game.columns[column_index]
	var guide_origin := _local_point(card_layer, guide.global_position)
	var x: float = guide_origin.x + (guide.size.x - CARD_SIZE.x) * 0.5
	var y: float = guide_origin.y + 10.0
	var raw_gaps: Array[float] = []
	var raw_total := 0.0
	for index in maxi(column.size() - 1, 0):
		var card := column[index] as Dictionary
		var gap := 26.0 if bool(card.get("face_up", false)) else 12.0
		raw_gaps.append(gap)
		raw_total += gap
	# 底部为静态 MessagePanel 留出空间；长牌列压缩间距，而不钻到提示条下方。
	var available := maxf(guide.size.y - CARD_SIZE.y - 68.0, 8.0)
	var compression := minf(1.0, available / raw_total) if raw_total > 0.0 else 1.0
	for index in column.size():
		result.append(Vector2(x, y))
		if index < raw_gaps.size():
			y += raw_gaps[index] * compression
	return result

#endregion

#region 拖拽交互


## 右键不进入拖拽状态，直接让纯规则模型选择目标并复用统一移动表现。
func _on_card_auto_move_requested(view: SpiderCardView) -> void:
	if _busy or _changing_scene or not _dragged_views.is_empty() or not view.face_up:
		return
	_hint_serial += 1
	_clear_column_highlight()
	var location := game.find_card(view.card_id)
	if location.is_empty():
		return
	var from_column := int(location["column"])
	var start_index := int(location["index"])
	if not game.is_movable_sequence(from_column, start_index):
		view.flash(DANGER, 0.30)
		_show_message("右键自动移动失败：这张牌上方必须全部同花色并逐张降序", 2.0, DANGER)
		return
	var target_column := game.find_auto_move_target(from_column, start_index)
	if target_column < 0:
		view.flash(UI.MUTED, 0.28)
		_show_message("当前没有可接收这组牌的目标列", 1.8, UI.MUTED)
		return
	var from_global := view.global_position + CARD_SIZE * 0.5
	var target_guide := _column_guides[target_column]
	var target_global := target_guide.global_position + Vector2(target_guide.size.x * 0.5, 28.0)
	_perform_move(from_column, start_index, target_column, from_global, target_global, true)


func _on_card_pressed(view: SpiderCardView) -> void:
	if _busy or _changing_scene or not _dragged_views.is_empty() or not view.face_up:
		return
	# 若上一条 H 提示仍在计时，拖拽应立即接管列高亮，旧回调也不能中途清掉它。
	_hint_serial += 1
	_clear_column_highlight()
	var location := game.find_card(view.card_id)
	if location.is_empty():
		return
	var column_index := int(location["column"])
	var start_index := int(location["index"])
	if not game.is_movable_sequence(column_index, start_index):
		view.flash(DANGER, 0.34)
		feedback_overlay.burst(_local_point(feedback_overlay, view.global_position + CARD_SIZE * 0.5), DANGER, 8)
		_show_message("只能一起移动同花色、逐张降序且全部翻开的牌组", 2.1, DANGER)
		return

	_drag_from_column = column_index
	_drag_start_index = start_index
	_dragged_views.clear()
	_drag_offsets.clear()
	var column := game.columns[column_index]
	for index in range(start_index, column.size()):
		var card_id := int(column[index].get("id", -1))
		var dragged_view := _card_views.get(card_id) as SpiderCardView
		if is_instance_valid(dragged_view):
			_dragged_views.append(dragged_view)

	if _dragged_views.is_empty():
		_cancel_drag()
		return
	for dragged_view in _dragged_views:
		dragged_view.reparent(drag_layer, true)
	var first_position := _dragged_views[0].position
	for index in _dragged_views.size():
		var dragged_view := _dragged_views[index]
		_drag_offsets.append(dragged_view.position - first_position)
		dragged_view.z_index = 1000 + index
		dragged_view.set_dragging(true)
	_drag_mouse_offset = drag_layer.get_local_mouse_position() - first_position
	_update_drag_position()


func _update_drag_position() -> void:
	if _dragged_views.is_empty():
		return
	var base_position := drag_layer.get_local_mouse_position() - _drag_mouse_offset
	for index in _dragged_views.size():
		_dragged_views[index].position = base_position + _drag_offsets[index]
	var target_column := _column_at_global_point(get_viewport().get_mouse_position())
	var valid := target_column >= 0 and game.can_move(_drag_from_column, _drag_start_index, target_column)
	_set_column_highlight(target_column, valid)


func _finish_drag() -> void:
	if _dragged_views.is_empty():
		return
	var target_column := _column_at_global_point(get_viewport().get_mouse_position())
	var from_global := _dragged_views[0].global_position + CARD_SIZE * 0.5
	var target_global := from_global
	if target_column >= 0:
		target_global = _column_guides[target_column].global_position + Vector2(_column_guides[target_column].size.x * 0.5, 28.0)
	var legal := target_column >= 0 and game.can_move(_drag_from_column, _drag_start_index, target_column)
	var from_column := _drag_from_column
	var start_index := _drag_start_index
	_end_drag_visuals()

	if not legal:
		_layout_all_cards(0.22)
		feedback_overlay.burst(_local_point(feedback_overlay, from_global), DANGER, 10)
		_show_message("这里接不上：目标列顶牌必须比所拖牌组的底牌大 1", 2.0, DANGER)
		return

	_perform_move(from_column, start_index, target_column, from_global, target_global)


## 拖拽和右键共用这一条提交路径，避免两套移动动画以后出现规则或性能差异。
func _perform_move(
	from_column: int,
	start_index: int,
	target_column: int,
	from_global: Vector2,
	target_global: Vector2,
	automatic := false
) -> bool:
	var destination_was_empty := game.columns[target_column].is_empty()
	var moving_card := game.columns[from_column][start_index] as Dictionary
	var same_suit_target := false
	if not destination_was_empty:
		var target_top := game.columns[target_column].back() as Dictionary
		same_suit_target = int(target_top.get("suit", -1)) == int(moving_card.get("suit", -2))
	var result := game.move_stack(from_column, start_index, target_column)
	if not bool(result.get("success", false)):
		_layout_columns([from_column, target_column], 0.22)
		_show_message(_reason_text(str(result.get("reason", ""))), 2.0, DANGER)
		return false

	var completion_time := _prepare_removed_views(result)
	_sync_board([], false, 0.20, [from_column, target_column])
	var accent := MINT if not automatic or same_suit_target else GOLD
	# 收组已有一次更强的共享反馈，不再叠加普通落牌的第二组蛛丝与粒子。
	if completion_time <= 0.0:
		feedback_overlay.thread_snap(_local_point(feedback_overlay, from_global), _local_point(feedback_overlay, target_global), accent)
		feedback_overlay.burst(_local_point(feedback_overlay, target_global), accent, 8)
	if automatic and completion_time <= 0.0:
		var moved_count := (result.get("moved_ids", []) as Array).size()
		if destination_was_empty:
			_show_message("右键自动移动：没有点数目标，已将 %d 张牌移入空列" % moved_count, 2.0, GOLD)
		elif same_suit_target:
			_show_message("右键自动移动：已将 %d 张牌接到同花色序列" % moved_count, 2.0, MINT)
		else:
			_show_message("右键自动移动：没有同花色目标，已将 %d 张牌接到其他花色" % moved_count, 2.2, GOLD)
	_pop_score()
	_lock_actions(maxf(0.24, completion_time + 0.10))
	return true


func _end_drag_visuals() -> void:
	for view in _dragged_views:
		if not is_instance_valid(view):
			continue
		view.set_dragging(false)
		view.reparent(card_layer, true)
	_dragged_views.clear()
	_drag_offsets.clear()
	_drag_from_column = -1
	_drag_start_index = -1
	_clear_column_highlight()


func _cancel_drag() -> void:
	if not _dragged_views.is_empty():
		_end_drag_visuals()
	_clear_column_highlight()

#endregion

#region 玩法动作


func _on_deal_pressed() -> void:
	if _busy or _changing_scene or not _dragged_views.is_empty():
		return
	# 先记住即将发出的十张牌。若最后一张恰好完成 K-A，它会立刻离开模型，
	# 这份短暂资料仍能让动画画出那张新牌；动作结束后不会长期保存副本。
	var pending_card_data: Dictionary = {}
	if game.stock.size() >= SpiderGameModel.STOCK_DEAL_SIZE:
		for offset in SpiderGameModel.STOCK_DEAL_SIZE:
			var card := game.stock[game.stock.size() - 1 - offset] as Dictionary
			pending_card_data[int(card.get("id", -1))] = card.duplicate(true)
	var result := game.deal_stock()
	if not bool(result.get("success", false)):
		var reason := str(result.get("reason", ""))
		_show_message(_reason_text(reason), 2.4, DANGER if reason == "empty_column" else GOLD)
		_shake_board(false)
		return

	_materialize_missing_removed_cards(result.get("removed_ids", []), pending_card_data)
	var completion_time := _prepare_removed_views(result)
	var dealt_ids := result.get("moved_ids", []) as Array
	_sync_board(dealt_ids, true, 0.28)
	var deal_origin := _local_point(feedback_overlay, deal_button.global_position + deal_button.size * 0.5)
	if completion_time <= 0.0:
		feedback_overlay.burst(deal_origin, GOLD, 14, Vector2.DOWN * 34.0)
	_show_message("蛛丝发牌：十列各增加一张，先观察新形成的连接", 2.1, GOLD)
	_pop_score()
	_lock_actions(maxf(0.62, completion_time + 0.10))


func _on_undo_pressed() -> void:
	if _busy or _changing_scene or not _dragged_views.is_empty():
		return
	var result := game.undo()
	if not bool(result.get("success", false)):
		_show_message("还没有可以撤销的动作", 1.8, UI.MUTED)
		return
	_sync_board([], false, 0.24)
	feedback_overlay.burst(_local_point(feedback_overlay, undo_button.global_position + undo_button.size * 0.5), CLIMAX, 14)
	_show_message("已恢复动作前的牌列、翻面、库存、步数和分数", 2.0, CLIMAX)
	_lock_actions(0.28)


func _prepare_removed_views(result: Dictionary) -> float:
	var removed_ids := result.get("removed_ids", []) as Array
	if removed_ids.is_empty():
		return 0.0
	var completed_delta := maxi(int(result.get("completed_delta", 0)), 1)
	var first_slot := maxi(game.completed_runs - completed_delta, 0)
	var first_origin := Vector2.ZERO
	var final_target := Vector2.ZERO
	var animated_count := 0
	var latest_end := 0.0

	for index in removed_ids.size():
		var card_id := int(removed_ids[index])
		var view := _card_views.get(card_id) as SpiderCardView
		if not is_instance_valid(view):
			continue
		if animated_count == 0:
			first_origin = _local_point(feedback_overlay, view.global_position + CARD_SIZE * 0.5)
		_card_views.erase(card_id)
		view.interactive = false
		view.z_index = 1500 + index
		var run_offset := index / SpiderGameModel.CARDS_PER_RUN
		var slot_index := clampi(first_slot + run_offset, 0, _completed_slots.size() - 1)
		var slot := _completed_slots[slot_index]
		var target := _local_point(card_layer, slot.global_position + slot.size * 0.5) - CARD_SIZE * 0.5
		final_target = _local_point(feedback_overlay, slot.global_position + slot.size * 0.5)
		# 一组牌共享 Overlay 光效，只让首、中、尾三张补充牌面闪光，避免 13 张
		# 程序化卡牌同时逐帧重绘。
		if index % SpiderGameModel.CARDS_PER_RUN in [0, 6, 12]:
			view.celebrate(float(index % SpiderGameModel.CARDS_PER_RUN) * 0.018)
		view.move_to(target + Vector2(float(index % 3 - 1) * 2.0, 0.0), 0.44, float(index) * 0.010)
		var vanish := create_tween()
		vanish.tween_interval(0.20 + float(index) * 0.010)
		vanish.set_parallel(true)
		vanish.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		vanish.tween_property(view, "scale", Vector2(0.28, 0.28), 0.42)
		vanish.tween_property(view, "rotation", (-0.08 if index % 2 == 0 else 0.08), 0.42)
		vanish.set_parallel(false)
		vanish.tween_callback(view.queue_free)
		latest_end = maxf(latest_end, 0.20 + float(index) * 0.010 + 0.42)
		animated_count += 1

	if animated_count > 0:
		feedback_overlay.completion_burst(first_origin, final_target)
		_play_completion_feedback(completed_delta)
	return latest_end


func _materialize_missing_removed_cards(removed_ids: Array, pending_data: Dictionary) -> void:
	for card_id_value in removed_ids:
		var card_id := int(card_id_value)
		if _card_views.has(card_id) or not pending_data.has(card_id):
			continue
		var card := (pending_data[card_id] as Dictionary).duplicate(true)
		# 这张牌已经由 deal_stock() 发到桌面，收组动画必须显示它的正面。
		card["face_up"] = true
		_create_card_view(card)


func _play_completion_feedback(completed_delta: int) -> void:
	var bonus := completed_delta * 100
	_show_big_feedback("蛛网闭合  +%d" % bonus, GOLD, 1.0)
	_flash_screen(GOLD, 0.18)
	_shake_board(true)
	_show_message("完整的 K → A 已自动收组！连续整理会获得更强反馈", 3.0, GOLD)
	_refresh_completed_slots()
	if game.is_won():
		_show_big_feedback("八组完成 · 蜘蛛大师", CLIMAX, 1.45)
		_flash_screen(CLIMAX, 0.26)


func _show_hint() -> void:
	# 切换场景时不再创建提示 Tween，避免离场瞬间产生无意义的短动画。
	if _busy or _changing_scene or not _dragged_views.is_empty():
		return
	for from_column in game.columns.size():
		var column := game.columns[from_column]
		for start_index in column.size():
			var to_column := game.find_auto_move_target(from_column, start_index)
			if to_column < 0:
				continue
			for index in range(start_index, column.size()):
				var view := _card_views.get(int(column[index].get("id", -1))) as SpiderCardView
				if is_instance_valid(view):
					view.flash(GOLD, 0.62)
			_set_column_highlight(to_column, true, true)
			var source_view := _card_views.get(int(column[start_index].get("id", -1))) as SpiderCardView
			if is_instance_valid(source_view):
				var from_point := _local_point(feedback_overlay, source_view.global_position + CARD_SIZE * 0.5)
				var guide := _column_guides[to_column]
				var to_point := _local_point(feedback_overlay, guide.global_position + Vector2(guide.size.x * 0.5, 34.0))
				feedback_overlay.thread_snap(from_point, to_point, GOLD)
			_show_message("提示：发光牌组可右键自动接到琥珀色列", 2.1, GOLD)
			_hint_serial += 1
			var serial := _hint_serial
			var hint_tween := create_tween()
			hint_tween.tween_interval(0.82)
			hint_tween.tween_callback(func() -> void:
				if serial == _hint_serial and _dragged_views.is_empty():
					_clear_column_highlight()
			)
			return
	_show_message("当前没有可直接连接的牌组，可以发牌或撤销", 2.2, UI.MUTED)

#endregion

#region 列目标、HUD 与操作锁


func _column_at_global_point(global_point: Vector2) -> int:
	var board_rect := board_stage.get_global_rect().grow(12.0)
	if not board_rect.has_point(global_point):
		return -1
	var nearest := -1
	var nearest_distance := INF
	for index in _column_guides.size():
		var guide := _column_guides[index]
		var center_x := guide.global_position.x + guide.size.x * 0.5
		var distance := absf(global_point.x - center_x)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = index
	return nearest if nearest_distance <= 58.0 else -1


func _set_column_highlight(column_index: int, valid: bool, hint := false) -> void:
	if column_index < 0 or column_index >= _column_guides.size():
		_clear_column_highlight()
		return
	if not hint and _highlighted_column == column_index and _highlight_is_valid == valid:
		return
	_clear_column_highlight()
	_highlighted_column = column_index
	_highlight_is_valid = valid
	var style := _hint_column_style if hint else (_valid_column_style if valid else _invalid_column_style)
	_column_guides[column_index].add_theme_stylebox_override("panel", style)


func _clear_column_highlight() -> void:
	if _highlighted_column >= 0 and _highlighted_column < _column_guides.size():
		_column_guides[_highlighted_column].add_theme_stylebox_override("panel", _normal_column_style)
	_highlighted_column = -1
	_highlight_is_valid = false


func _refresh_hud() -> void:
	moves_label.text = "步数  %d" % game.move_count
	score_label.text = "分数  %d" % game.score
	stock_label.text = "%s · 剩余发牌 %d" % [_difficulty_name(), game.get_stock_deals_remaining()]
	completed_label.text = "完整序列  %d / %d" % [game.completed_runs, SpiderGameModel.TOTAL_RUNS]
	_refresh_completed_slots()
	_refresh_difficulty_buttons()
	deal_button.disabled = _busy or not game.can_deal()
	undo_button.disabled = _busy or not game.can_undo()
	new_game_button.disabled = _busy


func _refresh_completed_slots() -> void:
	if _displayed_completed_runs == game.completed_runs:
		return
	_displayed_completed_runs = game.completed_runs
	for index in _completed_slots.size():
		var slot := _completed_slots[index]
		var filled := index < game.completed_runs
		slot.add_theme_stylebox_override("panel", _filled_run_style if filled else _empty_run_style)


func _set_busy(value: bool) -> void:
	if _busy == value:
		return
	_busy = value
	# _on_card_pressed() 已用 _busy 拒绝操作，锁定期间无需遍历 104 张牌切换输入。
	# interactive 只表达牌是否翻开；这样不会因一次动作制造整盘 Hover Tween。
	_refresh_hud()


func _lock_actions(duration: float) -> void:
	_busy_serial += 1
	var serial := _busy_serial
	_set_busy(true)
	var lock_tween := create_tween()
	lock_tween.tween_interval(maxf(duration, 0.01))
	lock_tween.tween_callback(func() -> void:
		if serial == _busy_serial:
			_set_busy(false)
	)

#endregion

#region 集中式视觉反馈


func _show_message(text: String, duration: float, accent: Color) -> void:
	message_label.text = text
	if _message_style:
		_message_style.border_color = accent.darkened(0.28)
	message_panel.modulate = Color.WHITE
	if _message_tween and _message_tween.is_valid():
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(maxf(duration, 0.1))
	_message_tween.tween_property(message_panel, "modulate:a", 0.46, 0.38)


func _show_big_feedback(text: String, color: Color, hold_time: float) -> void:
	if _feedback_tween and _feedback_tween.is_valid():
		_feedback_tween.kill()
	big_feedback.text = text
	big_feedback.add_theme_color_override("font_color", color)
	big_feedback.pivot_offset = big_feedback.size * 0.5
	big_feedback.scale = Vector2(0.62, 0.62)
	big_feedback.modulate.a = 0.0
	_feedback_tween = create_tween()
	_feedback_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_feedback_tween.set_parallel(true)
	_feedback_tween.tween_property(big_feedback, "scale", Vector2.ONE, 0.22)
	_feedback_tween.tween_property(big_feedback, "modulate:a", 1.0, 0.14)
	_feedback_tween.set_parallel(false)
	_feedback_tween.tween_interval(maxf(hold_time, 0.1))
	_feedback_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_feedback_tween.set_parallel(true)
	_feedback_tween.tween_property(big_feedback, "scale", Vector2(1.12, 1.12), 0.28)
	_feedback_tween.tween_property(big_feedback, "modulate:a", 0.0, 0.28)


func _flash_screen(color: Color, strength: float) -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	screen_flash.color = Color(color, clampf(strength, 0.0, 0.35))
	_flash_tween = create_tween()
	_flash_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(screen_flash, "color:a", 0.0, 0.42)


## 只晃动牌桌，不晃动标题、按钮与提示文字，保证反馈强烈但仍容易阅读。
func _shake_board(strong: bool) -> void:
	if _board_tween and _board_tween.is_valid():
		_board_tween.kill()
	board_stage.pivot_offset = board_stage.size * 0.5
	board_stage.rotation = 0.0
	board_stage.scale = Vector2.ONE * (1.010 if strong else 1.004)
	_board_tween = create_tween()
	_board_tween.set_trans(Tween.TRANS_SINE)
	var angle := 0.010 if strong else 0.004
	_board_tween.tween_property(board_stage, "rotation", -angle, 0.045)
	_board_tween.tween_property(board_stage, "rotation", angle * 0.78, 0.055)
	_board_tween.tween_property(board_stage, "rotation", -angle * 0.42, 0.055)
	_board_tween.tween_property(board_stage, "rotation", 0.0, 0.085)
	_board_tween.set_parallel(true)
	_board_tween.tween_property(board_stage, "scale", Vector2.ONE, 0.20)


func _pop_score() -> void:
	if _score_tween and _score_tween.is_valid():
		_score_tween.kill()
	score_label.pivot_offset = score_label.size * 0.5
	score_label.scale = Vector2.ONE
	_score_tween = create_tween()
	_score_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_score_tween.tween_property(score_label, "scale", Vector2(1.18, 1.18), 0.11)
	_score_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_score_tween.tween_property(score_label, "scale", Vector2.ONE, 0.16)

#endregion

#region 工具与场景切换


func _reason_text(reason: String) -> String:
	match reason:
		"empty_column": return "存在空列时不能发牌：先把任意牌组移入空列"
		"no_stock": return "库存已经发完，继续整理桌面上的牌"
		"no_history": return "还没有可以撤销的动作"
		"broken_sequence": return "整组移动必须全部翻开、同花色并逐张降序"
		"rank_mismatch": return "目标列顶牌必须比所拖牌组的底牌大 1"
		"same_column": return "牌组已经位于这一列"
		"already_won": return "八组序列已经全部完成"
		_: return "这个动作现在无法执行"


func _stock_origin_in(layer: Control) -> Vector2:
	# 起点藏在 Header 内、发牌按钮底缘附近；卡牌向下移动时才像从牌堆中抽出。
	var hidden_top_left := deal_button.global_position + Vector2(
		(deal_button.size.x - CARD_SIZE.x) * 0.5,
		deal_button.size.y - 18.0
	)
	return _local_point(layer, hidden_top_left)


## Control 没有 Node2D.to_local()；用 CanvasItem 的全局变换显式完成坐标转换。
## 集中到这里可避免拖拽层、卡牌层和特效层之间出现各自不同的换算方式。
func _local_point(control: Control, global_point: Vector2) -> Vector2:
	return control.get_global_transform().affine_inverse() * global_point


func _on_viewport_resized() -> void:
	board_stage.pivot_offset = board_stage.size * 0.5
	_layout_all_cards.call_deferred(0.0, {})
	queue_redraw()


func _return_to_menu() -> void:
	if _changing_scene:
		return
	_changing_scene = true
	_cancel_drag()
	if UFrame.transitions and await UFrame.transitions.change_scene(MENU_SCENE, 0.16):
		return
	get_tree().change_scene_to_file(MENU_SCENE)

#endregion
