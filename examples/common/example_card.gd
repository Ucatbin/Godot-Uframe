extends Button

## 启动器中的单张示例卡片。
##
## 静态结构保存在 example_card.tscn；脚本只注入不同示例的数据和少量交互动效。

#region 常量与场景引用
const UI := preload("res://examples/common/example_ui.gd")

## 下列引用都是模板中稳定存在的显示挂点，卡片数据不会创建第二套 UI 结构。
@onready var number_label: Label = $Margin/Column/Top/Number
@onready var genre_label: Label = $Margin/Column/Top/Genre
@onready var title_label: Label = $Margin/Column/Title
@onready var description_label: Label = $Margin/Column/Description
@onready var preview: Control = $Margin/Column/Preview
@onready var module_title: Label = $Margin/Column/ModuleTitle
@onready var chips: HFlowContainer = $Margin/Column/Chips
@onready var separator: HSeparator = $Margin/Column/Separator
@onready var controls_label: Label = $Margin/Column/Controls
@onready var enter_label: Label = $Margin/Column/Enter
#endregion

#region 运行时状态
## 启动器在实例入树前注入的单张卡片数据。
var _data: Dictionary
## 当前悬停或焦点缩放动画；新动画开始时停止旧动画。
var _animation_tween: Tween
#endregion

#region 生命周期
func _ready() -> void:
	# 子控件只负责显示，鼠标事件统一交给卡片根 Button。
	for child in find_children("*", "Control", true, false):
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_update_pivot)
	mouse_entered.connect(_animate.bind(Vector2(1.018, 1.018)))
	mouse_exited.connect(_animate.bind(Vector2.ONE))
	focus_entered.connect(_animate.bind(Vector2(1.012, 1.012)))
	focus_exited.connect(_animate.bind(Vector2.ONE))
	_update_pivot()
	if not _data.is_empty():
		_apply_data()
#endregion

#region 数据同步
## 注入一张卡片的数据。共享的 [code]CARD_SCENE[/code] 实例化后调用一次即可。
func configure(data: Dictionary) -> void:
	_data = data
	if is_node_ready():
		_apply_data()

func _apply_data() -> void:
	var accent: Color = _data.color
	UI.apply_button(self, accent)
	add_theme_stylebox_override("focus", UI.panel_style(UI.SURFACE_RAISED, accent, 14, 10))
	number_label.text = _data.number
	UI.style_label(number_label, 26, accent)
	genre_label.text = _data.genre
	UI.style_chip(genre_label, accent)
	title_label.text = _data.title
	UI.style_label(title_label, 25)
	description_label.text = _data.description
	UI.style_label(description_label, 15, UI.MUTED)
	preview.call("configure", _data.preview, accent)
	UI.style_label(module_title, 12, UI.MUTED.darkened(0.05))
	for child in chips.get_children():
		child.queue_free()
	for module_name: String in _data.modules:
		chips.add_child(UI.make_chip(module_name, accent))
	separator.modulate = Color(accent, 0.26)
	controls_label.text = _data.controls
	UI.style_label(controls_label, 13, UI.MUTED)
	UI.style_label(enter_label, 16, accent.lightened(0.18))
#endregion

#region 交互动效
func _update_pivot() -> void:
	pivot_offset = size * 0.5

func _animate(target_scale: Vector2) -> void:
	if _animation_tween and _animation_tween.is_valid():
		_animation_tween.kill()
	_animation_tween = create_tween().set_parallel()
	_animation_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_animation_tween.tween_property(self, "scale", target_scale, 0.14)
	_animation_tween.tween_property(
		self,
		"self_modulate",
		Color.WHITE if target_scale != Vector2.ONE else Color("#eef4ff"),
		0.14
	)
#endregion
