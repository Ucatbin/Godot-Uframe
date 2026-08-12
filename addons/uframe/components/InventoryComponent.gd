extends Node

## 事务式格子背包组件。
##
## 负责按 [StringName] ID 保存格子、堆叠规则与数量缓存，并提供添加、移动、拆分和整理操作。
## 不依赖物品 Resource 或 UI；View 只读取本模型并发送操作意图，不保存第二份背包规则。
## 打开 [code]examples/loot/loot_demo.tscn[/code] 可查看 64 格背包组件与格子 View 的组合。
class_name UFrameInventory

#region 信号
## 指定格子发生变化；批量操作会为每个受影响格子发出一次。
## [param index] 是发生变化的格子下标。
signal slot_changed(index: int)

## 一次完整背包操作提交后发出一次。
signal inventory_changed
#endregion

#region Inspector 配置
## 背包格子数量；缩小时若被移除区域仍有物品，本次修改会被拒绝。
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

## 物品没有独立规则时使用的堆叠上限；降低后若现有内容无法装下，本次修改会被拒绝。
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

## 物品 ID 到独立堆叠上限的映射；运行时应通过 [method set_stack_limit] 修改。
@export var stack_limits: Dictionary = {}
#endregion

#region 运行时状态
## 背包格子；空格使用空 [Dictionary]，非空格包含 [code]item_id[/code] 和 [code]count[/code]。
var _slots: Array[Dictionary] = []

## 物品 ID 到全部格子总数量的缓存。
var _totals: Dictionary[StringName, int] = {}
#endregion

#region 生命周期
## 按 Inspector 配置创建初始空格子。
func _init() -> void:
	_resize_slots()
#endregion

#region 背包操作
## 自动添加物品，优先填充同类堆叠，再使用空格。
## [param item_id] 是物品 ID，[param count] 是请求数量；返回实际加入数量。
func add_item(item_id: StringName, count: int = 1) -> int:
	if item_id.is_empty() or count <= 0:
		return 0
	var remaining := count
	var changed: Array[int] = []
	var stack_limit := get_stack_limit(item_id)
	# 优先填满同类堆叠，减少零散格子
	for index in slot_count:
		if remaining == 0:
			break
		if _slot_id(index) == item_id and _slot_count(index) < stack_limit:
			var moved := mini(remaining, stack_limit - _slot_count(index))
			_slots[index].count += moved
			remaining -= moved
			changed.append(index)
	# 再使用空格
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

## 从 [param index] 格移除请求的 [param count] 个物品，并返回实际移除数量。
func remove_from_slot(index: int, count: int = 1) -> int:
	if not _is_valid_index(index) or count <= 0 or _slots[index].is_empty():
		return 0
	var item_id := _slot_id(index)
	var removed := mini(count, _slot_count(index))
	_decrease_slot(index, removed)
	_change_total(item_id, -removed)
	_emit_changes([index])
	return removed

## 从 [param from_index] 向 [param to_index] 移动堆叠。
## [param amount] 为 [code]-1[/code] 时移动整个堆叠；目标为空时直接移动，同类合并至上限，异类仅整堆交换。
## 返回实际从源格移出的数量，失败返回 [code]0[/code]。
func move_stack(from_index: int, to_index: int, amount: int = -1) -> int:
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

## 把 [param from_index] 中向下取整的一半移动到空的 [param to_index]；失败返回 [code]0[/code]。
func split_half(from_index: int, to_index: int) -> int:
	if not _is_valid_index(from_index) or _slot_count(from_index) < 2:
		return 0
	if not _is_valid_index(to_index) or not _slots[to_index].is_empty():
		return 0
	return move_stack(from_index, to_index, _slot_count(from_index) / 2)

## 尽可能把 [param from_index] 合并到同类 [param to_index]，是 [method move_stack] 的语义入口。
func merge_stack(from_index: int, to_index: int) -> int:
	if _slot_id(from_index) != _slot_id(to_index):
		return 0
	return move_stack(from_index, to_index)

## 为 [param item_id] 设置独立堆叠上限 [param limit]。
## 新规则容量不足时返回 [code]false[/code]，并保持原规则和内容。
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

## 消耗 [param count] 个指定物品；总数量不足时不修改任何格子并返回 [code]false[/code]。
## 成功时只刷新一次总数缓存，并在完整操作结束后发出整体变化信号。
func consume_item(item_id: StringName, count: int = 1) -> bool:
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

## 从 [param index] 取出最多 [param amount] 个物品。
## 返回可由 [method place_stack] 放回的堆叠字典，失败时返回空字典。
func take_from_slot(index: int, amount: int = 1) -> Dictionary:
	if not _is_valid_index(index) or _slots[index].is_empty() or amount <= 0:
		return {}
	var item_id := _slot_id(index)
	var taken := mini(amount, _slot_count(index))
	var result := {"item_id": item_id, "count": taken}
	_decrease_slot(index, taken)
	_change_total(item_id, -taken)
	_emit_changes([index])
	return result

## 把外部 [param stack] 放入 [param index]，并返回未能放入的剩余堆叠。
## 目标为空或物品相同时可以放入，不同物品不会自动交换；[param amount] 为负数时尝试全部放入。
func place_stack(index: int, stack: Dictionary, amount: int = -1) -> Dictionary:
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

## 整理并合并全部堆叠。
## 可选 [param sort_key] 把物品 ID 映射为分类字符串，同类再按 ID 排列。
## 当前规则容量不足时返回 [code]false[/code]，且不修改任何格子。
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

## 清空全部格子；背包已经为空时不会发出变化信号。
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

## 从 [param saved_slots] 恢复全部格子，输入通常来自 [method get_slots]。
## 非法、超上限或超出容量的内容会使整个操作失败，原背包保持不变。
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
#endregion

#region 背包查询
## 获取 [param index] 的格子副本；无效下标或空格返回空字典。
func get_slot(index: int) -> Dictionary:
	if not _is_valid_index(index) or _slots[index].is_empty():
		return {}
	return _slots[index].duplicate()

## 判断 [param index] 是否为空；无效下标也视为空。
func is_slot_empty(index: int) -> bool:
	return not _is_valid_index(index) or _slots[index].is_empty()

## 获取 [param item_id] 的有效堆叠上限。
func get_stack_limit(item_id: StringName) -> int:
	return maxi(int(stack_limits.get(item_id, max_stack_size)), 1)

## 从缓存获取 [param item_id] 的总数量，调用成本固定。
func get_count(item_id: StringName) -> int:
	return _totals.get(item_id, 0)

## 判断是否拥有至少 [param count] 个 [param item_id]。
func has_item(item_id: StringName, count: int = 1) -> bool:
	return count > 0 and get_count(item_id) >= count

## 获取背包中全部物品的总数量。
func get_total_count() -> int:
	var total := 0
	for count: int in _totals.values():
		total += count
	return total

## 获取“物品 ID → 总数量”的缓存副本，适合不关心格子位置的界面。
func get_all_items() -> Dictionary[StringName, int]:
	return _totals.duplicate()

## 获取可保存的格子数组深层副本。
func get_slots() -> Array[Dictionary]:
	return _slots.duplicate(true)

## 获取当前已占用的格子数量。
func get_used_slot_count() -> int:
	var used := 0
	for slot in _slots:
		if not slot.is_empty():
			used += 1
	return used
#endregion

#region 内部数据维护
## 按 [member slot_count] 调整格子数组，重建缓存，并在运行期间按需发出整体变化信号。
func _resize_slots() -> void:
	var previous_size := _slots.size()
	_slots.resize(slot_count)
	for index in range(previous_size, slot_count):
		_slots[index] = {}
	_rebuild_totals()
	if is_inside_tree() and previous_size != slot_count:
		inventory_changed.emit()

## 检查从 [param first_removed_index] 开始的裁剪区域是否仍有物品。
func _has_items_after(first_removed_index: int) -> bool:
	for index in range(first_removed_index, _slots.size()):
		if not _slots[index].is_empty():
			return true
	return false

## 按当前格数与堆叠规则检查全部物品能否重新装箱，不修改格子。
func _can_pack_current_totals() -> bool:
	var required := 0
	for item_id: StringName in _totals:
		required += ceili(float(_totals[item_id]) / float(get_stack_limit(item_id)))
		if required > slot_count:
			return false
	return true

## 检查 [param index] 是否位于当前格子数组内。
func _is_valid_index(index: int) -> bool:
	return index >= 0 and index < _slots.size()

## 获取 [param index] 中的物品 ID；无效下标或空格返回空 [StringName]。
func _slot_id(index: int) -> StringName:
	if not _is_valid_index(index) or _slots[index].is_empty():
		return StringName()
	return StringName(_slots[index].item_id)

## 获取 [param index] 中的物品数量；无效下标或空格返回 [code]0[/code]。
func _slot_count(index: int) -> int:
	if not _is_valid_index(index) or _slots[index].is_empty():
		return 0
	return int(_slots[index].count)

## 从 [param index] 减少 [param amount] 个物品；数量归零时清空格子。
func _decrease_slot(index: int, amount: int) -> void:
	_slots[index].count -= amount
	if _slots[index].count <= 0:
		_slots[index] = {}

## 为 [param item_id] 的总数缓存应用 [param delta]；新总数不大于 [code]0[/code] 时移除条目。
func _change_total(item_id: StringName, delta: int) -> void:
	var next_total: int = _totals.get(item_id, 0) + delta
	if next_total <= 0:
		_totals.erase(item_id)
	else:
		_totals[item_id] = next_total

## 为 [param indices] 发出格子信号，并在存在变化时发出一次整体信号。
func _emit_changes(indices: Array[int]) -> void:
	for index in indices:
		slot_changed.emit(index)
	if not indices.is_empty():
		inventory_changed.emit()

## 为全部格子发出变化信号，再发出一次整体变化信号。
func _emit_all_slots_changed() -> void:
	for index in slot_count:
		slot_changed.emit(index)
	inventory_changed.emit()

## 根据当前格子完整重建物品总数缓存。
func _rebuild_totals() -> void:
	_totals.clear()
	for slot in _slots:
		if not slot.is_empty():
			var item_id := StringName(slot.item_id)
			_totals[item_id] = _totals.get(item_id, 0) + int(slot.count)
#endregion
