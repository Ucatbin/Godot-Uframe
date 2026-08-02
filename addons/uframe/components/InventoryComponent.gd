class_name UFrameInventory
extends Node

## UFrame 唯一的背包数据组件。
##
## 简单游戏只需使用 add_item/get_count/consume_item；格子游戏可继续使用 move_stack、[br]
## take_from_slot、place_stack 和 sort_and_merge。两类 API 始终操作同一份数据。[br]
## 默认提供 64 格。物品使用 StringName ID，UI 和物品 Resource 都不是本组件的依赖。[br]
## 任何可能丢失物品的配置变更都会被拒绝，背包始终保持“完整成功或原样不动”。

## 一个格子变化时发出。批量操作会为每个受影响格子发出一次。
signal slot_changed(index: int)
## 一次完整背包操作提交后发出一次。
signal inventory_changed

## 背包格子数量。缩小时若被移除区域仍有物品，本次修改会被拒绝。
@export_range(1, 1024) var slot_count := 64:
	set(value):
		var requested := maxi(value, 1)
		if requested == slot_count:
			return
		if requested < _slots.size() and _has_items_after(requested):
			push_warning("[UFrameInventory] 缩容会丢失物品，已拒绝修改")
			return
		slot_count = requested
		_resize_slots()

## 没有独立规则时使用的堆叠上限。降低后若现有物品无法装下，本次修改会被拒绝。
@export_range(1, 1000000) var max_stack_size := 99:
	set(value):
		var requested := maxi(value, 1)
		if requested == max_stack_size:
			return
		var previous := max_stack_size
		max_stack_size = requested
		if not _slots.is_empty() and not _can_pack_current_totals():
			max_stack_size = previous
			push_warning("[UFrameInventory] 新堆叠上限容量不足，已拒绝修改")
			return
		if not _totals.is_empty():
			sort_and_merge()

## 指定物品的独立堆叠上限。运行时修改请使用 set_stack_limit() 以获得事务保护。
@export var stack_limits: Dictionary = {}

var _slots: Array[Dictionary] = []
## 物品总数缓存，使 get_count() 的调用成本固定。
var _totals: Dictionary[StringName, int] = {}

func _init() -> void:
	_resize_slots()

## 获取格子副本。无效下标或空格返回空 Dictionary。
func get_slot(index: int) -> Dictionary:
	if not _is_valid_index(index) or _slots[index].is_empty():
		return {}
	return _slots[index].duplicate()

## 格子是否为空。无效下标也视为空。
func is_slot_empty(index: int) -> bool:
	return not _is_valid_index(index) or _slots[index].is_empty()

## 把物品自动加入已有堆叠和空格，返回实际加入数量。
func add_item(item_id: StringName, count := 1) -> int:
	if item_id.is_empty() or count <= 0:
		return 0
	var remaining := count
	var changed: Array[int] = []
	var stack_limit := get_stack_limit(item_id)
	# 优先填满同类堆叠，减少零散格子。
	for index in slot_count:
		if remaining == 0:
			break
		if _slot_id(index) == item_id and _slot_count(index) < stack_limit:
			var moved := mini(remaining, stack_limit - _slot_count(index))
			_slots[index].count += moved
			remaining -= moved
			changed.append(index)
	# 再使用空格。
	for index in slot_count:
		if remaining == 0:
			break
		if _slots[index].is_empty():
			var moved := mini(remaining, stack_limit)
			_slots[index] = {"item_id": item_id, "count": moved}
			remaining -= moved
			changed.append(index)
	var added := count - remaining
	if added > 0:
		_change_total(item_id, added)
		_emit_changes(changed)
	return added

## 从指定格移除数量并返回实际移除量。
func remove_from_slot(index: int, count := 1) -> int:
	if not _is_valid_index(index) or count <= 0 or _slots[index].is_empty():
		return 0
	var item_id := _slot_id(index)
	var removed := mini(count, _slot_count(index))
	_decrease_slot(index, removed)
	_change_total(item_id, -removed)
	_emit_changes([index])
	return removed

## 把物品从一个格子移动到另一个格子。
##
## amount 为 -1 表示整个堆叠。目标为空时直接移动；物品相同则合并至上限；[br]
## 物品不同且移动整个堆叠时交换位置。部分堆叠不能与不同物品交换。
## 返回实际从源格移出的数量，失败返回 0。
func move_stack(from_index: int, to_index: int, amount := -1) -> int:
	if not _is_valid_index(from_index) or not _is_valid_index(to_index) or from_index == to_index:
		return 0
	if _slots[from_index].is_empty():
		return 0
	var source_count := _slot_count(from_index)
	var requested := source_count if amount < 0 else mini(amount, source_count)
	if requested <= 0:
		return 0
	if _slots[to_index].is_empty():
		var moved := mini(requested, get_stack_limit(_slot_id(from_index)))
		_slots[to_index] = {"item_id": _slot_id(from_index), "count": moved}
		_decrease_slot(from_index, moved)
		_emit_changes([from_index, to_index])
		return moved
	if _slot_id(from_index) == _slot_id(to_index):
		var moved := mini(requested, get_stack_limit(_slot_id(to_index)) - _slot_count(to_index))
		if moved <= 0:
			return 0
		_slots[to_index].count += moved
		_decrease_slot(from_index, moved)
		_emit_changes([from_index, to_index])
		return moved
	if requested == source_count:
		var temporary := _slots[to_index]
		_slots[to_index] = _slots[from_index]
		_slots[from_index] = temporary
		_emit_changes([from_index, to_index])
		return source_count
	return 0

## 将源格的一半移动到空目标格。奇数数量时移动向下取整的一半。
func split_half(from_index: int, to_index: int) -> int:
	if not _is_valid_index(from_index) or _slot_count(from_index) < 2:
		return 0
	if not _is_valid_index(to_index) or not _slots[to_index].is_empty():
		return 0
	return move_stack(from_index, to_index, _slot_count(from_index) / 2)

## 将源格尽可能合并到同类目标格。它是 move_stack(from, to) 的语义别名。
func merge_stack(from_index: int, to_index: int) -> int:
	if _slot_id(from_index) != _slot_id(to_index):
		return 0
	return move_stack(from_index, to_index)

## 设置一种物品的独立堆叠上限。容量不足时返回 false 并保持原规则和内容。
func set_stack_limit(item_id: StringName, limit: int) -> bool:
	if item_id.is_empty():
		return false
	var had_previous := stack_limits.has(item_id)
	var previous := stack_limits.get(item_id)
	stack_limits[item_id] = maxi(limit, 1)
	if not _can_pack_current_totals():
		if had_previous:
			stack_limits[item_id] = previous
		else:
			stack_limits.erase(item_id)
		return false
	if get_count(item_id) > 0:
		sort_and_merge()
	return true

## 获取物品的堆叠上限。
func get_stack_limit(item_id: StringName) -> int:
	return maxi(int(stack_limits.get(item_id, max_stack_size)), 1)

## 获取一种物品在全部格子中的总数量，调用成本固定。
func get_count(item_id: StringName) -> int:
	return _totals.get(item_id, 0)

## 是否至少拥有 count 个指定物品。
func has_item(item_id: StringName, count := 1) -> bool:
	return count > 0 and get_count(item_id) >= count

## 仅在总数量足够时消耗物品。整个操作只刷新一次缓存并发送一次整体信号。
func consume_item(item_id: StringName, count := 1) -> bool:
	if not has_item(item_id, count):
		return false
	var remaining := count
	var changed: Array[int] = []
	for index in _slots.size():
		if _slot_id(index) != item_id:
			continue
		var removed := mini(remaining, _slot_count(index))
		_decrease_slot(index, removed)
		remaining -= removed
		changed.append(index)
		if remaining == 0:
			break
	_change_total(item_id, -count)
	_emit_changes(changed)
	return true

## 获取背包中全部物品的总数量。
func get_total_count() -> int:
	var total := 0
	for count: int in _totals.values():
		total += count
	return total

## 返回“物品 ID → 总数量”的副本，适合不关心格子位置的界面。
func get_all_items() -> Dictionary[StringName, int]:
	return _totals.duplicate()

## 从格子取出指定数量，返回一个可由 place_stack() 放回的堆叠 Dictionary。
func take_from_slot(index: int, amount := 1) -> Dictionary:
	if not _is_valid_index(index) or _slots[index].is_empty() or amount <= 0:
		return {}
	var item_id := _slot_id(index)
	var taken := mini(amount, _slot_count(index))
	var result := {"item_id": item_id, "count": taken}
	_decrease_slot(index, taken)
	_change_total(item_id, -taken)
	_emit_changes([index])
	return result

## 尝试把外部堆叠放入指定格，返回未能放入的剩余堆叠。
## 目标为空或物品相同时可以放入；不同物品不会自动交换鼠标携带内容。
func place_stack(index: int, stack: Dictionary, amount := -1) -> Dictionary:
	if not _is_valid_index(index) or stack.is_empty():
		return stack.duplicate()
	var item_id := StringName(stack.get("item_id", ""))
	var source_count := maxi(int(stack.get("count", 0)), 0)
	if item_id.is_empty() or source_count == 0:
		return {}
	if not _slots[index].is_empty() and _slot_id(index) != item_id:
		return stack.duplicate()
	var requested := source_count if amount < 0 else mini(amount, source_count)
	var free_space := get_stack_limit(item_id) - _slot_count(index)
	var placed := mini(requested, free_space)
	if placed <= 0:
		return stack.duplicate()
	if _slots[index].is_empty():
		_slots[index] = {"item_id": item_id, "count": placed}
	else:
		_slots[index].count += placed
	_change_total(item_id, placed)
	_emit_changes([index])
	var remaining := source_count - placed
	return {} if remaining == 0 else {"item_id": item_id, "count": remaining}

## 自动合并全部同类堆叠并排列到前部。
##
## sort_key 可把物品 ID 映射到分类字符串，例如材料、消耗品、装备；同类再按 ID 排列。[br]
## 若当前规则下容量不足，本方法返回 false 且不会修改任何格子。
func sort_and_merge(sort_key: Callable = Callable()) -> bool:
	if not _can_pack_current_totals():
		return false
	var item_ids: Array = _totals.keys()
	var keys := {}
	if sort_key.is_valid():
		for item_id: StringName in item_ids:
			keys[item_id] = String(sort_key.call(item_id))
	item_ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		var a_key := String(keys.get(a, ""))
		var b_key := String(keys.get(b, ""))
		return String(a) < String(b) if a_key == b_key else a_key < b_key
	)
	var next_slots: Array[Dictionary] = []
	next_slots.resize(slot_count)
	for index in slot_count:
		next_slots[index] = {}
	var write_index := 0
	for item_id: StringName in item_ids:
		var remaining: int = _totals[item_id]
		var limit := get_stack_limit(item_id)
		while remaining > 0:
			var packed_count := mini(remaining, limit)
			next_slots[write_index] = {"item_id": item_id, "count": packed_count}
			remaining -= packed_count
			write_index += 1
	_slots = next_slots
	_emit_all_slots_changed()
	return true

## 清空全部格子。
func clear() -> void:
	var changed: Array[int] = []
	for index in slot_count:
		if not _slots[index].is_empty():
			_slots[index] = {}
			changed.append(index)
	if changed.is_empty():
		return
	_totals.clear()
	_emit_changes(changed)

## 返回可直接保存的深层副本。
func get_slots() -> Array[Dictionary]:
	return _slots.duplicate(true)

## 从存档恢复格子。非法、超上限或超出容量的内容会使整个操作失败，原背包保持不变。
func set_slots(saved_slots: Array) -> bool:
	for index in range(slot_count, saved_slots.size()):
		if saved_slots[index] is Dictionary and not (saved_slots[index] as Dictionary).is_empty():
			return false
	var next_slots: Array[Dictionary] = []
	next_slots.resize(slot_count)
	for index in slot_count:
		next_slots[index] = {}
		if index >= saved_slots.size() or saved_slots[index] == null:
			continue
		if not saved_slots[index] is Dictionary:
			return false
		var entry := saved_slots[index] as Dictionary
		if entry.is_empty():
			continue
		var item_id := StringName(entry.get("item_id", ""))
		var count := int(entry.get("count", 0))
		if item_id.is_empty() or count <= 0 or count > get_stack_limit(item_id):
			return false
		next_slots[index] = {"item_id": item_id, "count": count}
	_slots = next_slots
	_rebuild_totals()
	_emit_all_slots_changed()
	return true

## 返回当前占用的格子数。
func get_used_slot_count() -> int:
	var used := 0
	for slot in _slots:
		if not slot.is_empty():
			used += 1
	return used

func _resize_slots() -> void:
	var previous_size := _slots.size()
	_slots.resize(slot_count)
	for index in range(previous_size, slot_count):
		_slots[index] = {}
	_rebuild_totals()
	if is_inside_tree() and previous_size != slot_count:
		inventory_changed.emit()

func _has_items_after(first_removed_index: int) -> bool:
	for index in range(first_removed_index, _slots.size()):
		if not _slots[index].is_empty():
			return true
	return false

func _can_pack_current_totals() -> bool:
	var required := 0
	for item_id: StringName in _totals:
		required += ceili(float(_totals[item_id]) / float(get_stack_limit(item_id)))
		if required > slot_count:
			return false
	return true

func _is_valid_index(index: int) -> bool:
	return index >= 0 and index < _slots.size()

func _slot_id(index: int) -> StringName:
	if not _is_valid_index(index) or _slots[index].is_empty():
		return StringName()
	return StringName(_slots[index].item_id)

func _slot_count(index: int) -> int:
	if not _is_valid_index(index) or _slots[index].is_empty():
		return 0
	return int(_slots[index].count)

func _decrease_slot(index: int, amount: int) -> void:
	_slots[index].count -= amount
	if _slots[index].count <= 0:
		_slots[index] = {}

func _change_total(item_id: StringName, delta: int) -> void:
	var next_total: int = _totals.get(item_id, 0) + delta
	if next_total <= 0:
		_totals.erase(item_id)
	else:
		_totals[item_id] = next_total

func _emit_changes(indices: Array[int]) -> void:
	for index in indices:
		slot_changed.emit(index)
	if not indices.is_empty():
		inventory_changed.emit()

func _emit_all_slots_changed() -> void:
	for index in slot_count:
		slot_changed.emit(index)
	inventory_changed.emit()

func _rebuild_totals() -> void:
	_totals.clear()
	for slot in _slots:
		if not slot.is_empty():
			var item_id := StringName(slot.item_id)
			_totals[item_id] = _totals.get(item_id, 0) + int(slot.count)
