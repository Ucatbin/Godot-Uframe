extends Control

## UFrame 示例启动器。每张卡片都说明玩法、操作和正在展示的公共模块。

const UI := preload("res://examples/common/example_ui.gd")
const CardScene := preload("res://examples/common/example_card.tscn")

const EXAMPLES := [
	{
		"number": "01",
		"genre": "ACTION · 2D",
		"title": "生存竞技场",
		"description": "玩家移动收纳在 BehaviorManager 下；战斗能力由 Health、Team、Hitbox 与 Hurtbox 子组件组合。",
		"controls": "WASD 移动 · 自动射击",
		"preview": &"arena",
		"modules": ["Behavior", "Pool", "Hitbox 2D"],
		"scene": "res://examples/arena/arena_demo.tscn",
		"color": Color("#ff6b7a"),
	},
	{
		"number": "02",
		"genre": "PLATFORM · 2D",
		"title": "单屏平台跳跃",
		"description": "StateMachine 直接挂在 Player 下；Idle、Run、Air 节点真正执行移动、跳跃、重力与状态转换。",
		"controls": "A / D 移动 · Space 跳跃",
		"preview": &"platformer",
		"modules": ["Input", "FSM", "Camera 2D"],
		"scene": "res://examples/platformer/platformer_demo.tscn",
		"color": Color("#5ca8ff"),
	},
	{
		"number": "03",
		"genre": "SYSTEMS · UI",
		"title": "掉落与背包工坊",
		"description": "Inventory 是 Player 的场景组件；物品与掉落表来自 .tres，64 个重复格子来自可复用 View 场景。",
		"controls": "拖拽 · 右键 · Ctrl + 右键",
		"preview": &"inventory",
		"modules": ["Registry", "Loot", "Inventory"],
		"scene": "res://examples/loot/loot_demo.tscn",
		"color": Color("#66d9a0"),
	},
	{
		"number": "04",
		"genre": "CARDS · UI",
		"title": "蜘蛛纸牌",
		"description": "固定十列与三档难度直接写在场景中；右键会按同花、异花、空列顺序自动落牌。",
		"controls": "拖拽 / 右键自动移动 · 1/2/4 · H 提示",
		"preview": &"spider",
		"modules": ["Rules", "Card View", "Tween"],
		"scene": "res://examples/spider/spider_demo.tscn",
		"color": Color("#74f0c1"),
	},
]

var _opening := false
var _cards: Array[Button] = []

@onready var _cards_container: HBoxContainer = $Content/Column/CardsScroll/CardPadding/Cards
@onready var _title: Label = $Content/Column/Header/Title
@onready var _version: Label = $Content/Column/Header/Version
@onready var _subtitle: Label = $Content/Column/Subtitle
@onready var _footer_hint: Label = $Content/Column/Footer/Hint
@onready var _footer_note: Label = $Content/Column/Footer/Note

func _ready() -> void:
	_style_static_interface()
	# 四张同构卡片来自数据数组，属于合理的重复运行时内容；
	# 背景、标题、容器和页脚则都能直接在场景树中查看与调整。
	for example in EXAMPLES:
		_cards_container.add_child(_create_example_card(example))
	if not _cards.is_empty():
		_cards[0].grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or _opening:
		return
	var index := -1
	match key.keycode:
		KEY_1: index = 0
		KEY_2: index = 1
		KEY_3: index = 2
		KEY_4: index = 3
	if index >= 0:
		_open_example(EXAMPLES[index].scene)
		get_viewport().set_input_as_handled()

func _style_static_interface() -> void:
	UI.style_label(_title, 34)
	_version.text = "UFRAME %s  ·  GODOT 4.7" % UFrame.VERSION
	UI.style_chip(_version, Color("#6f8cff"))
	UI.style_label(_subtitle, 16, UI.MUTED)
	UI.style_label(_footer_hint, 14, UI.MUTED.lightened(0.14))
	UI.style_label(_footer_note, 13, Color("#8da4ff"))

func _create_example_card(example: Dictionary) -> Button:
	var card := CardScene.instantiate() as Button
	card.call("configure", example)
	card.pressed.connect(func() -> void: _open_example(example.scene))
	_cards.append(card)
	return card

func _open_example(scene_path: String) -> void:
	if _opening:
		return
	_opening = true
	for card in _cards:
		card.disabled = true
	if UFrame.transitions and await UFrame.transitions.change_scene(scene_path, 0.16):
		return
	get_tree().change_scene_to_file(scene_path)
