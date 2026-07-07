# ============================================================
# InventoryComponent.gd  — 背包组件
# 挂载到玩家节点上，管理道具/物品的增删查
#
# 用法：
#   1. 把 InventoryComponent 挂到玩家节点下
#   2. 添加物品：inventory.add_item("potion", 3)
#   3. 消耗物品：inventory.consume_item("potion", 1)
#   4. 查询：inventory.get_count("potion")
# ============================================================

class_name InventoryComponent
extends Node

## 背包容量（0 = 无限）
@export var capacity: int = 0

## 物品数据：{ item_id: count }
var items: Dictionary = {}

#region 信号

## 背包内容变化（item_id, 旧数量, 新数量）
signal item_changed(item_id: String, old_count: int, new_count: int)

## 背包满了（添加失败）
signal inventory_full(item_id: String)

#endregion

#region 公开方法

## 添加物品，返回实际添加的数量（容量不足时可能小于请求数量）
func add_item(item_id: String, count: int = 1) -> int:
	if count <= 0:
		return 0

	var old = items.get(item_id, 0)
	var max_add = count

	# 检查容量
	if capacity > 0:
		var current_total = _get_total_count()
		var free_space = capacity - current_total
		if free_space <= 0:
			inventory_full.emit(item_id)
			return 0
		max_add = min(count, free_space)

	items[item_id] = old + max_add
	item_changed.emit(item_id, old, items[item_id])
	return max_add

## 移除物品，返回实际移除的数量
func remove_item(item_id: String, count: int = 1) -> int:
	if count <= 0:
		return 0
	if not items.has(item_id):
		return 0

	var old = items[item_id]
	var actual = min(old, count)
	items[item_id] = old - actual

	if items[item_id] == 0:
		items.erase(item_id)

	item_changed.emit(item_id, old, items.get(item_id, 0))
	return actual

## 获取某个物品的数量
func get_count(item_id: String) -> int:
	return items.get(item_id, 0)

## 是否拥有某物品（数量 >= 1）
func has_item(item_id: String) -> bool:
	return items.get(item_id, 0) > 0

## 消耗物品（和 remove_item 一样，语义更清晰）
func consume_item(item_id: String, count: int = 1) -> bool:
	if get_count(item_id) < count:
		return false
	remove_item(item_id, count)
	return true

## 清空背包
func clear() -> void:
	items.clear()

## 获取所有物品（返回副本，防止外部修改）
func get_all_items() -> Dictionary:
	return items.duplicate()

#endregion

#region 内部方法

func _get_total_count() -> int:
	var total = 0
	for count in items.values():
		total += count
	return total

#endregion
