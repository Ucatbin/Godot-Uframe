extends Resource

## 无状态加权掉落表
##
## 不保存连续未掉落次数，同一个 [code].tres[/code] 可以被多个调用者安全共享[br]
## 调用者把上次结果中的 [code]miss_count[/code] 传给下一次抽取，以分别维护保底状态[br][br]
## [code]示例：[/code]
## [codeblock]
## var result := table.roll(miss_count)
## miss_count = result["miss_count"]
## if result["count"] > 0:
##     inventory.add_item(result["content_id"], result["count"])
## [/codeblock]
class_name UFrameLootTable

#region 配置
## [b]掉落条目[/b]
@export var entries: Array[UFrameLootEntry] = []

## [b]无掉落权重[/b][br]
## [code]0[/code] 表示每次都尝试选择有效条目
@export_range(0.0, 1000000.0) var no_drop_weight := 0.0

## [b]保底次数[/b][br]
## 连续未掉落达到该次数后触发；[code]0[/code] 表示关闭保底
@export_range(0, 1000000) var pity_count := 0

## [b]保底条目下标[/b][br]
## 下标或对应条目无效时不会触发保底
@export var pity_entry_index := -1
#endregion

#region 主要方法
## [b]抽取一次掉落[/b][br]
## 返回值固定包含 [code]content_id[/code]、[code]count[/code]、[code]miss_count[/code] 和 [code]pity_triggered[/code][br]
## 传入随机数生成器后可获得可复现结果[br][br]
## [param miss_count] : 调用者此前连续未掉落的次数[br]
## [param rng] : 可选的随机数生成器
func roll(miss_count := 0, rng: RandomNumberGenerator = null) -> Dictionary:
	miss_count = maxi(miss_count, 0)
	if _should_trigger_pity(miss_count):
		var pity_result := _make_result(entries[pity_entry_index], rng)
		if pity_result.count > 0:
			pity_result["miss_count"] = 0
			pity_result["pity_triggered"] = true
			return pity_result
	var result := _roll_weighted(rng)
	var dropped: bool = result.count > 0 and not StringName(result.content_id).is_empty()
	result["miss_count"] = 0 if dropped else miss_count + 1
	result["pity_triggered"] = false
	return result

## [b]连续抽取并合并结果[/b][br]
## 返回 [code]drops[/code] 数组和下一次应继续使用的 [code]miss_count[/code][br][br]
## [param times] : 抽取次数[br]
## [param miss_count] : 调用者此前连续未掉落的次数[br]
## [param rng] : 可选的随机数生成器
func roll_multi(times: int, miss_count := 0, rng: RandomNumberGenerator = null) -> Dictionary:
	var totals: Dictionary[StringName, int] = {}
	var current_misses := maxi(miss_count, 0)
	for _index in maxi(times, 0):
		var result := roll(current_misses, rng)
		current_misses = result.miss_count
		if result.count > 0:
			totals[result.content_id] = totals.get(result.content_id, 0) + result.count
	var drops: Array[Dictionary] = []
	for content_id: StringName in totals:
		drops.append({"content_id": content_id, "count": totals[content_id]})
	return {"drops": drops, "miss_count": current_misses}
#endregion

#region 查询方法
## [b]获取全部有效内容 ID[/b][br]
## 返回不重复的 ID 数组，可用于进入关卡前预加载资源
func get_all_content_ids() -> Array[StringName]:
	var unique: Dictionary[StringName, bool] = {}
	for entry in entries:
		if _is_eligible(entry):
			unique[entry.content_id] = true
	return unique.keys()
#endregion

#region 内部方法
## [b]执行一次加权抽取[/b][br][br]
## [param rng] : 可选的随机数生成器
func _roll_weighted(rng: RandomNumberGenerator) -> Dictionary:
	var total_weight := maxf(no_drop_weight, 0.0)
	for entry in entries:
		if _is_eligible(entry):
			total_weight += entry.weight
	if total_weight <= 0.0:
		return _empty_result()
	var random_value := (rng.randf() if rng else randf()) * total_weight
	var cumulative := maxf(no_drop_weight, 0.0)
	if random_value < cumulative:
		return _empty_result()
	for entry in entries:
		if not _is_eligible(entry):
			continue
		cumulative += entry.weight
		if random_value < cumulative:
			return _make_result(entry, rng)
	return _empty_result()

## [b]判断是否触发保底[/b][br][br]
## [param miss_count] : 调用者此前连续未掉落的次数
func _should_trigger_pity(miss_count: int) -> bool:
	return pity_count > 0 \
		and miss_count >= pity_count \
		and pity_entry_index >= 0 \
		and pity_entry_index < entries.size() \
		and _is_eligible(entries[pity_entry_index])

## [b]判断条目是否有效[/b][br][br]
## [param entry] : 需要检查的掉落条目
func _is_eligible(entry: UFrameLootEntry) -> bool:
	return entry != null \
		and not entry.content_id.is_empty() \
		and entry.weight > 0.0 \
		and maxi(entry.min_count, entry.max_count) > 0

## [b]生成掉落结果[/b][br][br]
## [param entry] : 选中的掉落条目[br]
## [param rng] : 可选的随机数生成器
func _make_result(entry: UFrameLootEntry, rng: RandomNumberGenerator) -> Dictionary:
	var minimum := maxi(entry.min_count, 0)
	var maximum := maxi(entry.max_count, minimum)
	var count := rng.randi_range(minimum, maximum) if rng else randi_range(minimum, maximum)
	return _empty_result() if count <= 0 else {"content_id": entry.content_id, "count": count}

## [b]生成空结果[/b]
func _empty_result() -> Dictionary:
	return {"content_id": StringName(), "count": 0}
#endregion
