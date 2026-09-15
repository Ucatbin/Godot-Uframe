extends Control

## 掉落与背包示例的薄控制器。
##
## 打开 loot_demo.tscn 可以直接看到 Player/InventoryComponent、完整 UI 和
## SlotGrid 挂载点；掉落表与物品资料则来自 Inspector 引用的 .tres。
## 唯一动态生成的正式 UI 是数量取决于 InventoryComponent.slot_count 的重复格子。

#region 配置
const UI := preload("res://examples/common/example_ui.gd")
const SAVE_SLOT := "uframe_loot_demo"
const MENU_SCENE := "res://examples/example_browser.tscn"

## 纯配置资源：权重、数量范围和保底规则都可以在 Inspector 中修改。
@export var loot_table: UFrameLootTable
## 示例物品的静态资料。它们是 LootDemoItemData .tres，而不是运行时临时对象。
@export var item_definitions: Array[LootDemoItemData] = []
## 单个格子的可复用场景模板；实际数量由 InventoryComponent.slot_count 决定。
@export var slot_scene: PackedScene
#endregion

#region 场景引用
## 场景中静态挂载的唯一背包组件。
@onready var inventory: UFrameInventory = %InventoryComponent
## 运行时重复格子的固定布局挂点。
@onready var slot_grid: GridContainer = %SlotGrid
## 最近一次掉落或背包操作结果。
@onready var result_label: Label = %ResultLabel
## 背包容量和总数量摘要。
@onready var inventory_summary: Label = %InventorySummary
## 跟随鼠标显示当前拿起堆叠的标签。
@onready var cursor_label: Label = %CursorLabel
## 当前保底进度文本。
@onready var pity_label: Label = %PityLabel
## 当前保底进度条。
@onready var pity_bar: ProgressBar = %PityBar
## 鼠标悬停格子的物品详情。
@onready var item_detail: Label = %ItemDetail
#endregion

#region 运行时状态
## 当前示例已经抽取的次数。
var roll_count := 0
## 连续未命中保底物品的次数；由调用方持有，不写回共享掉落表。
var pity_misses := 0
## 与背包格子索引一一对应的重复 View。
var slot_buttons: Array[InventorySlotButton] = []
## 鼠标当前携带的临时堆叠；空 Dictionary 表示没有拿起物品。
var cursor_stack: Dictionary = {}
## 防止连续提交多次返回菜单请求。
var _changing_scene := false
#endregion

#region 生命周期
func _ready() -> void:
	_style_static_interface()
	if not _has_valid_configuration():
		return
	_register_item_data()
	_create_repeated_slot_views()
	pity_bar.max_value = loot_table.pity_count
	_seed_inventory()
	_refresh_all_slots()
	_refresh_summary()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"ui_cancel"):
		_return_to_menu()
	cursor_label.global_position = get_viewport().get_mouse_position() + Vector2(14, 14)
#endregion

#region 场景装配
## 检查场景中必须由开发者配置的资源，缺失时给出容易理解的错误。
func _has_valid_configuration() -> bool:
	if loot_table == null:
		push_error("[LootDemo] 请在 LootDemo 根节点配置 Loot Table 资源")
		return false
	if slot_scene == null:
		push_error("[LootDemo] 请在 LootDemo 根节点配置 Slot Scene")
		return false
	if item_definitions.is_empty():
		push_error("[LootDemo] 请在 LootDemo 根节点配置 Item Definitions")
		return false
	return true

## 把 Inspector 中配置的物品 Resource 注册到 UFrame Registry。
## Registry 只负责运行时按 ID 查询，物品内容仍以 .tres 为唯一配置来源。
func _register_item_data() -> void:
	for data in item_definitions:
		if data == null or data.id.is_empty():
			push_warning("[LootDemo] 已跳过空物品资源或空 ID")
			continue
		if not UFrame.registry.has_value(&"demo_item", data.id):
			UFrame.registry.register(&"demo_item", data.id, data)

## SlotGrid 本身是静态场景节点；这里只按组件容量实例化同构的格子模板。
## 这样修改格子样式只需编辑一个 inventory_slot_button.tscn，也无需手工复制 64 次。
func _create_repeated_slot_views() -> void:
	for index in inventory.slot_count:
		var slot := slot_scene.instantiate() as InventorySlotButton
		if slot == null:
			push_error("[LootDemo] Slot Scene 的根节点必须使用 InventorySlotButton")
			return
		slot.inventory = inventory
		slot.slot_index = index
		slot.pressed.connect(_place_cursor_stack.bind(index))
		slot.right_clicked.connect(_on_slot_right_clicked)
		slot.item_dropped.connect(_on_item_dropped)
		slot.slot_hovered.connect(_show_slot_detail)
		slot_grid.add_child(slot)
		slot_buttons.append(slot)

## 节点和布局都在 .tscn 中；这里仅复用公共样式函数，避免复制大量 StyleBox。
func _style_static_interface() -> void:
	UI.apply_panel(%RollPanel, Color("#66d9a0"), 16)
	UI.apply_panel(%InventoryPanel, Color("#5ca8ff"), 16)
	UI.apply_panel(%DetailPanel, Color("#7890aa"), 11)
	UI.apply_button(%BackButton, Color("#7890aa"))
	UI.apply_button(%RollButton, Color("#66d9a0"), true)
	UI.apply_button(%SaveButton, Color("#5ca8ff"))
	UI.apply_button(%LoadButton, Color("#c083ff"))
	UI.apply_button(%SortButton, Color("#ffca70"))
	UI.apply_button(%ResetButton, Color("#66d9a0"))
	UI.apply_button(%ClearButton, Color("#ff6b7a"))
	UI.style_chip(%MaterialChip, Color("#b9855d"))
	UI.style_chip(%ConsumableChip, Color("#ff7196"))
	UI.style_chip(%EquipmentChip, Color("#c8d5e2"))
	UI.style_progress_bar(pity_bar, Color("#c083ff"))
	cursor_label.add_theme_stylebox_override("normal", UI.panel_style(UI.SURFACE_RAISED, Color("#66d9a0"), 8, 9))
#endregion

#region 掉落与显示
## 恢复教学用的零散堆叠，让玩家进入场景后可以立即体验拖拽与整理。
func _seed_inventory() -> void:
	cursor_stack = {}
	roll_count = 0
	pity_misses = 0
	inventory.set_slots([
		{"item_id": &"demo:wood", "count": 31},
		{"item_id": &"demo:potion", "count": 7},
		{"item_id": &"demo:sword", "count": 1},
		{"item_id": &"demo:coin", "count": 42},
		{}, {}, {}, {},
		{"item_id": &"demo:wood", "count": 18},
		{"item_id": &"demo:gem", "count": 5},
		{"item_id": &"demo:potion", "count": 6},
		{"item_id": &"demo:crown", "count": 1},
		{}, {}, {}, {},
		{"item_id": &"demo:stone", "count": 54},
		{"item_id": &"demo:bomb", "count": 3},
		{"item_id": &"demo:shield", "count": 1},
		{"item_id": &"demo:coin", "count": 17},
	])
	result_label.text = "已预置零散堆叠：现在就能拖拽、拆分、合并或自动整理。"
	_update_cursor_label()

func _roll_once() -> void:
	if not cursor_stack.is_empty():
		result_label.text = "请先放下鼠标携带的物品，再进行抽取。"
		return
	if Input.is_key_pressed(KEY_SHIFT):
		_roll_batch()
		return
	roll_count += 1
	var result := loot_table.roll(pity_misses)
	pity_misses = result.miss_count
	if result.count == 0:
		result_label.text = "第 %d 次：什么都没有，保底进度 +1。" % roll_count
	else:
		var added := inventory.add_item(result.content_id, result.count)
		var data := _get_item_data(result.content_id)
		var suffix := "（保底触发）" if result.pity_triggered else ""
		result_label.text = "第 %d 次：获得 %s × %d %s" % [roll_count, data.display_name, added, suffix]
		if added < result.count:
			result_label.text += "；背包空间不足，剩余掉落未拾取。"
	_refresh_summary()

## Shift 抽取十次，展示掉落合并与一次背包事务；未装下的数量由玩法明确反馈。
func _roll_batch() -> void:
	var result := loot_table.roll_multi(10, pity_misses)
	pity_misses = result.miss_count
	roll_count += 10
	var requested: Dictionary[StringName, int] = {}
	var requested_count := 0
	for drop: Dictionary in result.drops:
		requested[drop.content_id] = drop.count
		requested_count += int(drop.count)
	var added := inventory.add_items(requested)
	var added_count := 0
	for item_id: StringName in added:
		added_count += added[item_id]
	result_label.text = "十连抽取完成：装入 %d 件，%d 件未拾取。" % [added_count, requested_count - added_count]
	_refresh_summary()

func _refresh_slot(index: int) -> void:
	if index < 0 or index >= slot_buttons.size():
		return
	var entry := inventory.get_slot(index)
	var data := _get_item_data(entry.item_id) if not entry.is_empty() else null
	var limit := inventory.get_stack_limit(entry.item_id) if not entry.is_empty() else 1
	slot_buttons[index].set_entry(entry, data, limit)

func _refresh_all_slots() -> void:
	for index in slot_buttons.size():
		_refresh_slot(index)

func _refresh_summary() -> void:
	inventory_summary.text = "已使用 %d / %d 格　·　物品总数 %d　·　场景组件：Player/InventoryComponent" % [
		inventory.get_used_slot_count(),
		inventory.slot_count,
		inventory.get_total_count(),
	]
	pity_label.text = "保底 %d / %d" % [pity_misses, loot_table.pity_count]
	pity_bar.value = pity_misses
	_update_cursor_label()

func _show_slot_detail(index: int) -> void:
	var entry := inventory.get_slot(index)
	if entry.is_empty():
		item_detail.text = "第 %d 格为空。拖拽物品到这里即可移动或拆分堆叠。" % (index + 1)
		return
	var data := _get_item_data(entry.item_id)
	var category_name: String = {
		&"material": "材料",
		&"consumable": "消耗品",
		&"equipment": "装备",
	}.get(data.category, "其他")
	item_detail.text = "%s  × %d\n%s · 堆叠上限 %d\n%s" % [
		data.display_name,
		entry.count,
		category_name,
		inventory.get_stack_limit(entry.item_id),
		data.description,
	]
#endregion

#region 背包交互
func _on_slot_right_clicked(index: int, half: bool) -> void:
	if cursor_stack.is_empty():
		var slot := inventory.get_slot(index)
		if slot.is_empty():
			return
		var amount := maxi(int(slot.count) / 2, 1) if half else 1
		cursor_stack = inventory.take_from_slot(index, amount)
	else:
		var amount := maxi(int(cursor_stack.count) / 2, 1) if half else 1
		cursor_stack = inventory.place_stack(index, cursor_stack, amount)
	_update_cursor_label()

func _on_item_dropped(from_index: int, to_index: int) -> void:
	result_label.text = "已将第 %d 格移动到第 %d 格。" % [from_index + 1, to_index + 1]

func _place_cursor_stack(index: int) -> void:
	if cursor_stack.is_empty():
		return
	cursor_stack = inventory.place_stack(index, cursor_stack)
	_update_cursor_label()

func _update_cursor_label() -> void:
	if cursor_stack.is_empty():
		cursor_label.text = ""
		cursor_label.visible = false
	else:
		var data := _get_item_data(cursor_stack.item_id)
		cursor_label.text = "%s  × %d" % [data.display_name, cursor_stack.count]
		cursor_label.visible = true

func _return_cursor_to_inventory() -> bool:
	if cursor_stack.is_empty():
		return true
	var item_id := StringName(cursor_stack.item_id)
	var count := int(cursor_stack.count)
	var added := inventory.add_item(item_id, count)
	if added == count:
		cursor_stack = {}
		_update_cursor_label()
		return true
	cursor_stack.count = count - added
	result_label.text = "背包已满，无法自动放回鼠标物品；请先腾出空间。"
	_update_cursor_label()
	return false
#endregion

#region 存档
func _save_game() -> void:
	if not _return_cursor_to_inventory():
		return
	# 存档对象是一次运行时快照，因此按需创建，而不是放入场景树。
	var data := LootDemoSaveData.new()
	data.slots = inventory.get_slots()
	data.roll_count = roll_count
	data.pity_misses = pity_misses
	result_label.text = "保存成功。" if UFrame.save.save(data, SAVE_SLOT) else "保存失败。"

func _load_game() -> void:
	if not _return_cursor_to_inventory():
		return
	var data := UFrame.save.load(SAVE_SLOT) as LootDemoSaveData
	if data == null:
		result_label.text = "没有可读取的本示例存档。"
		return
	if not inventory.set_slots(data.slots):
		result_label.text = "存档内容不符合当前背包规则，已保持原背包不变。"
		return
	roll_count = data.roll_count
	pity_misses = data.pity_misses
	result_label.text = "读取成功，共进行过 %d 次抽取。" % roll_count
	_refresh_summary()
#endregion

#region 背包命令
func _clear_inventory() -> void:
	cursor_stack = {}
	inventory.clear()
	result_label.text = "背包已清空；点击“重置示例”可恢复教学物品。"
	_update_cursor_label()

func _sort_inventory() -> void:
	if not _return_cursor_to_inventory():
		return
	if inventory.sort_and_merge(_item_sort_key):
		result_label.text = "已按材料 → 消耗品 → 装备排列，并自动合并同类堆叠。"
	else:
		result_label.text = "当前堆叠规则容量不足，整理已安全取消，物品没有变化。"
#endregion

#region 查询
func _item_sort_key(item_id: StringName) -> String:
	var data := _get_item_data(item_id)
	return "%02d:%s" % [data.category_order, String(item_id)]

func _get_item_data(item_id: StringName) -> LootDemoItemData:
	return UFrame.registry.get_value(&"demo_item", item_id) as LootDemoItemData
#endregion

#region 场景切换
func _return_to_menu() -> void:
	if _changing_scene or not _return_cursor_to_inventory():
		return
	_changing_scene = true
	if UFrame.transitions and await UFrame.transitions.change_scene(MENU_SCENE, 0.14):
		return
	get_tree().change_scene_to_file(MENU_SCENE)
#endregion
