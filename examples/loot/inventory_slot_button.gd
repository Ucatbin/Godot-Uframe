class_name InventorySlotButton
extends Button

## 背包示例的可拖拽格子视图。
##
## 这个脚本随 inventory_slot_button.tscn 一起复用，只负责显示物品和转发手势；
## 数量、移动、合并等规则仍全部位于场景树中的 UFrameInventory 组件。

const UI := preload("res://examples/common/example_ui.gd")

signal right_clicked(index: int, half: bool)
signal item_dropped(from_index: int, to_index: int)
signal slot_hovered(index: int)

var inventory: UFrameInventory
var slot_index := -1
var _entry: Dictionary = {}
var _title := ""
var _description := ""
var _icon_kind := &""
var _item_color := Color("#42526a")
var _stack_limit := 1
var _drop_hint := 0

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UI.apply_button(self, Color("#40506a"))
	add_theme_stylebox_override("normal", UI.panel_style(Color("#101722"), Color("#2a384c"), 7, 3))
	add_theme_stylebox_override("hover", UI.panel_style(Color("#172232"), Color("#5ca8ff"), 7, 3))
	gui_input.connect(_on_gui_input)
	mouse_exited.connect(func() -> void:
		_drop_hint = 0
		queue_redraw()
	)
	mouse_entered.connect(func() -> void: slot_hovered.emit(slot_index))
	resized.connect(func() -> void: pivot_offset = size * 0.5)

## 更新格子显示。空 Dictionary 会恢复为空格外观。
func set_entry(entry: Dictionary, data: LootDemoItemData = null, stack_limit := 1) -> void:
	_entry = entry.duplicate()
	_stack_limit = stack_limit
	if entry.is_empty() or data == null:
		_title = ""
		_description = ""
		_icon_kind = &""
		_item_color = Color("#42526a")
		tooltip_text = "空格 %d" % (slot_index + 1)
	else:
		_title = data.display_name
		_description = data.description
		_icon_kind = data.icon_kind
		_item_color = data.display_color
		tooltip_text = "%s × %d / %d\n%s" % [_title, entry.count, _stack_limit, _description]
	queue_redraw()

func _get_drag_data(_position: Vector2) -> Variant:
	if inventory == null or inventory.is_slot_empty(slot_index):
		return null
	var preview := PanelContainer.new()
	UI.apply_panel(preview, _item_color, 9)
	var label := UI.make_label("%s  × %d" % [_title, _entry.count], 15, _item_color.lightened(0.25))
	preview.add_child(label)
	set_drag_preview(preview)
	modulate.a = 0.38
	return {"source_index": slot_index}

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	var valid: bool = inventory != null \
		and data is Dictionary \
		and data.has("source_index") \
		and int(data.source_index) != slot_index
	_drop_hint = 1 if valid else -1
	queue_redraw()
	return valid

func _drop_data(_position: Vector2, data: Variant) -> void:
	var source_index := int(data.source_index)
	var moved := inventory.move_stack(source_index, slot_index)
	_drop_hint = 0
	modulate.a = 1.0
	if moved > 0:
		item_dropped.emit(source_index, slot_index)
		var tween := create_tween()
		scale = Vector2(1.12, 1.12)
		tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "scale", Vector2.ONE, 0.18)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		modulate.a = 1.0
		_drop_hint = 0
		queue_redraw()

func _on_gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse and mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
		right_clicked.emit(slot_index, Input.is_key_pressed(KEY_CTRL))
		accept_event()

func _draw() -> void:
	if _drop_hint != 0:
		var hint_color := Color("#66d9a0") if _drop_hint > 0 else Color("#ff6b7a")
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color(hint_color, 0.12), true)
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), hint_color, false, 2.0)
	if _entry.is_empty():
		var font := get_theme_default_font()
		draw_string(font, Vector2(6, 14), str(slot_index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(Color("#7890aa"), 0.28))
		return
	_draw_item_icon(size * 0.5 + Vector2(0, -2))
	var count_text := str(_entry.count)
	var font := get_theme_default_font()
	draw_string(font, Vector2(3, size.y - 5), count_text, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 7, 13, Color.WHITE)
	if _stack_limit == 1:
		draw_circle(Vector2(size.x - 8, 8), 3.0, Color("#ffca70"))

func _draw_item_icon(center: Vector2) -> void:
	var dark := _item_color.darkened(0.38)
	match _icon_kind:
		&"coin":
			draw_circle(center, 11.0, dark)
			draw_circle(center, 8.0, _item_color)
			draw_circle(center - Vector2(2, 2), 2.5, _item_color.lightened(0.35))
		&"gem":
			var points := PackedVector2Array([center + Vector2(0, -12), center + Vector2(10, -3), center + Vector2(6, 10), center + Vector2(-6, 10), center + Vector2(-10, -3)])
			draw_colored_polygon(points, _item_color)
			draw_polyline(points + PackedVector2Array([points[0]]), _item_color.lightened(0.30), 2.0)
		&"potion":
			draw_rect(Rect2(center + Vector2(-7, -7), Vector2(14, 17)), dark, true)
			draw_circle(center + Vector2(0, 3), 7.0, _item_color)
			draw_rect(Rect2(center + Vector2(-4, -12), Vector2(8, 5)), _item_color.lightened(0.25), true)
		&"bomb":
			draw_circle(center + Vector2(0, 2), 10.0, dark)
			draw_arc(center + Vector2(6, -7), 7.0, PI, PI * 1.55, 8, _item_color.lightened(0.35), 2.0)
			draw_circle(center + Vector2(10, -12), 2.5, Color("#ffca70"))
		&"sword":
			draw_line(center + Vector2(-8, 10), center + Vector2(8, -10), _item_color.lightened(0.25), 5.0)
			draw_line(center + Vector2(-10, 2), center + Vector2(-2, 10), dark, 4.0)
		&"shield":
			var shield := PackedVector2Array([center + Vector2(0, -12), center + Vector2(10, -7), center + Vector2(8, 6), center + Vector2(0, 12), center + Vector2(-8, 6), center + Vector2(-10, -7)])
			draw_colored_polygon(shield, _item_color)
			draw_polyline(shield + PackedVector2Array([shield[0]]), dark, 2.0)
		&"crown":
			var crown := PackedVector2Array([center + Vector2(-11, 8), center + Vector2(-10, -7), center + Vector2(-3, 0), center + Vector2(0, -10), center + Vector2(5, 0), center + Vector2(11, -7), center + Vector2(10, 8)])
			draw_colored_polygon(crown, _item_color)
		_:
			draw_rect(Rect2(center - Vector2(10, 10), Vector2(20, 20)), dark, true)
			draw_rect(Rect2(center - Vector2(8, 8), Vector2(16, 16)), _item_color, true)
