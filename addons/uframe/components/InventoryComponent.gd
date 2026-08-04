extends Node

## 事务式格子背包组件
##
## 通过 [StringName] ID 管理物品，不依赖 UI 或物品资源类型[br]
## 简单项目可使用 [method add_item]、[method get_count] 和 [method consume_item]；格子界面可使用移动、拆分与放置 API[br]
## 任何可能丢失物品的配置或存档变更都会被整体拒绝
class_name UFrameInventory

#region 信号
## [b]格子变化[/b][br]
## 批量操作会为每个受影响格子发出一次[br][br]
## [param index] : 发生变化的格子下标
signal slot_changed(index: int)

## [b]背包操作完成[/b][br]
## 一次完整操作提交后发出一次
signal inventory_changed
#endregion

#region 配置
## [b]背包格子数量[/b][br]
## 缩小时若被移除区域仍有物品，本次修改会被拒绝
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

## [b]默认堆叠上限[/b][br]
## 物品没有独立规则时使用；降低后若现有内容无法装下，本次修改会被拒绝
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

## [b]独立堆叠上限[/b][br]
## [color=cyan]映射：[/color]物品 ID → 堆叠上限。运行时应通过 [method set_stack_limit] 修改
@export var stack_limits: Dictionary = {}
#endregion

#region 运行时状态
## [b]背包格子[/b][br]
## 空格使用空 [Dictionary]，非空格包含 [code]item_id[/code] 和 [code]count[/code]
var _slots: Array[Dictionary] = []

## [b]物品总数缓存[/b][br][br]
## [color=cyan]映射：[/color]物品 ID → 全部格子的总数量。
var _totals: Dictionary[StringName, int] = {}
#endregion

#region 生命周期
func _init() -> void:
	_resize_slots()
#endregion

#region 主要方法
## [b]自动添加物品[/b][br]
## 优先填充已有同类堆叠，再使用空格；返回实际加入数量[br][br]
## [param item_id] : 物品 ID[br]
## [param count] : 请求添加数量
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

## [b]从格子移除物品[/b][br]
## 返回实际移除数量[br][br]
## [param index] : 格子下标[br]
## [param count] : 请求移除数量
func remove_from_slot(index: int, count := 1) -> int:
	if not _is_valid_index(index) or count <= 0 or _slots[index].is_empty():
		return 0
	var item_id := _slot_id(index)
	var removed := mini(count, _slot_count(index))
	_decrease_slot(index, removed)
	_change_total(item_id, -removed)
	_emit_changes([index])
	return removed

## [b]移动物品堆叠[/b][br]
## [param amount] 为 [code]-1[/code] 时移动整个堆叠[br]
## 目标为空时直接移动，同类物品合并至上限，异类物品仅在移动整个堆叠时交换[br]
## 返回实际从源格移出的数量，失败返回 [code]0[/code][br][br]
## [param from_index] : 源格下标[br]
## [param to_index] : 目标格下标[br]
## [param amount] : 请求移动数量
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

## [b]拆分一半堆叠[/b][br]
## 只接受空目标格；奇数数量时移动向下取整的一半[br][br]
## [param from_index] : 源格下标[br]
## [param to_index] : 空目标格下标
func split_half(from_index: int, to_index: int) -> int:
	if not _is_valid_index(from_index) or _slot_count(from_index) < 2:
		return 0
	if not _is_valid_index(to_index) or not _slots[to_index].is_empty():
		return 0
	return move_stack(from_index, to_index, _slot_count(from_index) / 2)

## [b]合并物品堆叠[/b][br]
## 尽可能合并到同类目标格，是 [method move_stack] 的语义别名[br][br]
## [param from_index] : 源格下标[br]
## [param to_index] : 同类目标格下标
func merge_stack(from_index: int, to_index: int) -> int:
	if _slot_id(from_index) != _slot_id(to_index):
		return 0
	return move_stack(from_index, to_index)

## [b]设置独立堆叠上限[/b][br]
## 新规则容量不足时返回 [code]false[/code]，并保持原规则和内容[br][br]
## [param item_id] : 物品 ID[br]
## [param limit] : 新的堆叠上限
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

## [b]消耗指定物品[/b][br]
## 仅在总数量足够时执行，整个操作只刷新一次缓存并发出一次整体信号[br][br]
## [param item_id] : 物品 ID[br]
## [param count] : 请求消耗数量
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

## [b]从格子取出堆叠[/b][br]
## 返回可由 [method place_stack] 放回的堆叠字典[br][br]
## [param index] : 格子下标[br]
## [param amount] : 请求取出数量
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

## [b]把外部堆叠放入格子[/b][br]
## 目标为空或物品相同时可以放入，不同物品不会自动交换[br]
## 返回未能放入的剩余堆叠[br][br]
## [param index] : 目标格下标[br]
## [param stack] : 包含 [code]item_id[/code] 和 [code]count[/code] 的外部堆叠[br]
## [param amount] : 请求放入数量，负数表示全部
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

## [b]整理并合并全部堆叠[/b][br]
## 可选回调把物品 ID 映射为分类字符串，同类再按 ID 排列[br]
## 当前规则容量不足时返回 [code]false[/code]，且不会修改任何格子[br][br]
## [param sort_key] : 可选的“物品 ID → 分类字符串”回调
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

## [b]清理全部格子[/b][br]
## 背包已经为空时不会发出信号
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

## [b]恢复已保存格子[/b][br]
## 非法、超上限或超出容量的内容会使整个操作失败，原背包保持不变[br][br]
## [param saved_slots] : 由 [method get_slots] 生成或采用相同结构的格子数组
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

#region 查询方法
## [b]获取格子内容[/b][br]
## 返回字典副本；无效下标或空格返回空字典[br][br]
## [param index] : 格子下标
func get_slot(index: int) -> Dictionary:
	if not _is_valid_index(index) or _slots[index].is_empty():
		return {}
	return _slots[index].duplicate()

## [b]判断格子是否为空[/b][br]
## 无效下标也视为空[br][br]
## [param index] : 格子下标
func is_slot_empty(index: int) -> bool:
	return not _is_valid_index(index) or _slots[index].is_empty()

## [b]获取物品堆叠上限[/b][br][br]
## [param item_id] : 物品 ID
func get_stack_limit(item_id: StringName) -> int:
	return maxi(int(stack_limits.get(item_id, max_stack_size)), 1)

## [b]获取物品总数量[/b][br]
## 使用缓存，调用成本固定[br][br]
## [param item_id] : 物品 ID
func get_count(item_id: StringName) -> int:
	return _totals.get(item_id, 0)

## [b]判断是否拥有物品[/b][br][br]
## [param item_id] : 物品 ID[br]
## [param count] : 所需数量
func has_item(item_id: StringName, count := 1) -> bool:
	return count > 0 and get_count(item_id) >= count

## [b]获取全部物品数量[/b]
func get_total_count() -> int:
	var total := 0
	for count: int in _totals.values():
		total += count
	return total

## [b]获取物品数量表[/b][br]
## 返回“物品 ID → 总数量”的副本，适合不关心格子位置的界面
func get_all_items() -> Dictionary[StringName, int]:
	return _totals.duplicate()

## [b]获取可保存格子数据[/b][br]
## 返回格子数组的深层副本
func get_slots() -> Array[Dictionary]:
	return _slots.duplicate(true)

## [b]获取已占用格子数[/b]
func get_used_slot_count() -> int:
	var used := 0
	for slot in _slots:
		if not slot.is_empty():
			used += 1
	return used
#endregion

#region 内部方法
## [b]调整格子数组大小[/b][br]
## 重建总数缓存，并在运行期间按需发出整体变化信号
func _resize_slots() -> void:
	var previous_size := _slots.size()
	_slots.resize(slot_count)
	for index in range(previous_size, slot_count):
		_slots[index] = {}
	_rebuild_totals()
	if is_inside_tree() and previous_size != slot_count:
		inventory_changed.emit()

## [b]检查裁剪区域是否有物品[/b][br][br]
## [param first_removed_index] : 即将移除区域的首个下标
func _has_items_after(first_removed_index: int) -> bool:
	for index in range(first_removed_index, _slots.size()):
		if not _slots[index].is_empty():
			return true
	return false

## [b]检查当前内容能否重新装箱[/b][br]
## 按现有格数与堆叠规则计算，不修改格子
func _can_pack_current_totals() -> bool:
	var required := 0
	for item_id: StringName in _totals:
		required += ceili(float(_totals[item_id]) / float(get_stack_limit(item_id)))
		if required > slot_count:
			return false
	return true

## [b]检查格子下标[/b][br][br]
## [param index] : 需要检查的下标
func _is_valid_index(index: int) -> bool:
	return index >= 0 and index < _slots.size()

## [b]获取格子物品 ID[/b][br]
## 无效下标或空格返回空 [StringName][br][br]
## [param index] : 格子下标
func _slot_id(index: int) -> StringName:
	if not _is_valid_index(index) or _slots[index].is_empty():
		return StringName()
	return StringName(_slots[index].item_id)

## [b]获取格子物品数量[/b][br]
## 无效下标或空格返回 [code]0[/code][br][br]
## [param index] : 格子下标
func _slot_count(index: int) -> int:
	if not _is_valid_index(index) or _slots[index].is_empty():
		return 0
	return int(_slots[index].count)

## [b]减少格子物品数量[/b][br]
## 数量降到 [code]0[/code] 时清空格子[br][br]
## [param index] : 格子下标[br]
## [param amount] : 减少数量
func _decrease_slot(index: int, amount: int) -> void:
	_slots[index].count -= amount
	if _slots[index].count <= 0:
		_slots[index] = {}

## [b]修改物品总数缓存[/b][br]
## 新总数不大于 [code]0[/code] 时移除对应条目[br][br]
## [param item_id] : 物品 ID[br]
## [param delta] : 数量变化
func _change_total(item_id: StringName, delta: int) -> void:
	var next_total: int = _totals.get(item_id, 0) + delta
	if next_total <= 0:
		_totals.erase(item_id)
	else:
		_totals[item_id] = next_total

## [b]发出局部变化信号[/b][br][br]
## [param indices] : 本次操作发生变化的格子下标
func _emit_changes(indices: Array[int]) -> void:
	for index in indices:
		slot_changed.emit(index)
	if not indices.is_empty():
		inventory_changed.emit()

## [b]发出全部格子变化信号[/b]
func _emit_all_slots_changed() -> void:
	for index in slot_count:
		slot_changed.emit(index)
	inventory_changed.emit()

## [b]重建物品总数缓存[/b]
func _rebuild_totals() -> void:
	_totals.clear()
	for slot in _slots:
		if not slot.is_empty():
			var item_id := StringName(slot.item_id)
			_totals[item_id] = _totals.get(item_id, 0) + int(slot.count)
#endregion
