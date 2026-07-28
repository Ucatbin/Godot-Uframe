extends Resource

'''
描述：
	掉落表 Resource
	定义怪物的掉落物品及概率，支持加权随机

用法：
	1. 在编辑器中新建 Resource，类型选 LootTable
	2. 在 Inspector 中编辑 loot_entries 数组
	3. 代码中调用：
	   var item = loot_table.roll()
'''

class_name LootTable

#region 变量
## [b]掉落条目列表[/b]
@export var loot_entries: Array[Dictionary] = []

## [b]保底掉落次数[/b][br]
## 连续不掉的次数达到此值时，强制掉落
@export var pity_count: int = 0

## [b]保底条目索引[/b][br]
## 保底时必定掉落的条目下标（-1 表示不启用保底）
@export var pity_entry_index: int = -1

## [b]缓存的总权重[/b][br]
## -1 表示未计算，由 roll() 首次调用时自动计算[br]
## 运行时修改 loot_entries 后需调用 recalculate() 刷新
var _total_weight: float = -1.0
#endregion

#region 公共方法
## [b]掷一次掉落表，返回物品 ID 和数量[/b][br]
## 返回 {"item_id": "", "count": 0}，无掉落时 count 为 0
func roll() -> Dictionary:
	if loot_entries.is_empty():
		return {"item_id": "", "count": 0}

	if _total_weight < 0.0:
		_calc_total_weight()

	if _total_weight <= 0.0:
		return {"item_id": "", "count": 0}

	var r := randf() * _total_weight
	var cumulative := 0.0
	for entry in loot_entries:
		cumulative += entry.get("weight", 1.0)
		if r <= cumulative:
			var item_id: String = entry.get("item_id", "")
			var min_c: int = entry.get("min_count", 1)
			var max_c: int = entry.get("max_count", 1)
			var count := randi() % (max_c - min_c + 1) + min_c
			return {"item_id": item_id, "count": count}

	return {"item_id": "", "count": 0}

## [b]掷多次（模拟多物品掉落）[/b]
func roll_multi(times: int) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for i in times:
		var result := roll()
		if result.count > 0:
			# 合并相同物品
			var merged := false
			for r in results:
				if r.item_id == result.item_id:
					r.count += result.count
					merged = true
					break
			if not merged:
				results.append(result)
	return results

## [b]获取所有可能的物品 ID（用于预加载）[/b]
func get_all_item_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry in loot_entries:
		var item_id: String = entry.get("item_id", "")
		if not item_id.is_empty() and item_id not in ids:
			ids.append(item_id)
	return ids

## [b]强制重新计算权重缓存[/b][br]
## 运行时修改 loot_entries 后必须调用此方法
func recalculate() -> void:
	_calc_total_weight()

## [b]获取当前总权重[/b]（调试用）
func get_total_weight() -> float:
	if _total_weight < 0.0:
		_calc_total_weight()
	return _total_weight
#endregion

#region 内部方法
func _calc_total_weight() -> void:
	_total_weight = 0.0
	for entry in loot_entries:
		_total_weight += entry.get("weight", 1.0)
#endregion
