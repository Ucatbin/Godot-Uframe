extends Resource

## 无状态加权掉落表
##
## 在 Inspector 中组合 [UFrameLootEntry]，负责加权抽取、空掉落和保底规则。
## 本 Resource 不保存连续未掉落次数，因此同一个 [code].tres[/code] 可以被多个调用者安全共享。
## 调用者把上次结果中的 [code]miss_count[/code] 传给下一次抽取，分别维护各自的保底状态。
##
## 使用示例：
## [codeblock]
## var result := table.roll(miss_count)
## miss_count = result["miss_count"]
## if result["count"] > 0:
##     inventory.add_item(result["content_id"], result["count"])
## [/codeblock]
class_name UFrameLootTable

#region Inspector 配置
## 参与抽取的掉落条目。
@export var entries: Array[UFrameLootEntry] = []

## 无掉落权重；[code]0[/code] 表示每次都尝试选择有效条目。
@export_range(0.0, 1000000.0) var no_drop_weight := 0.0

## 连续未掉落达到该次数后触发保底；[code]0[/code] 表示关闭保底。
@export_range(0, 1000000) var pity_count := 0

## 保底条目下标；下标或对应条目无效时不会触发保底。
@export var pity_entry_index := -1
#endregion

#region 主要方法
## 抽取一次掉落。
## 返回值固定包含 [code]content_id[/code]、[code]count[/code]、[code]miss_count[/code] 和
## [code]pity_triggered[/code]；传入 [param rng] 后可获得可复现结果。
func roll(miss_count: int = 0, rng: RandomNumberGenerator = null) -> Dictionary:
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

## 连续抽取并按内容 ID 合并结果。
## 返回 [code]drops[/code] 数组和下一次应继续使用的 [code]miss_count[/code]。
func roll_multi(times: int, miss_count: int = 0, rng: RandomNumberGenerator = null) -> Dictionary:
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
## 返回全部有效且不重复的内容 ID，可用于进入关卡前预加载资源。
func get_all_content_ids() -> Array[StringName]:
	var unique: Dictionary[StringName, bool] = {}
	for entry in entries:
		if _is_eligible(entry):
			unique[entry.content_id] = true
	return unique.keys()
#endregion

#region 内部方法
## 执行一次包含空掉落权重的加权抽取。
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

## 判断当前连续未掉落次数是否满足有效保底配置。
func _should_trigger_pity(miss_count: int) -> bool:
	return pity_count > 0 \
		and miss_count >= pity_count \
		and pity_entry_index >= 0 \
		and pity_entry_index < entries.size() \
		and _is_eligible(entries[pity_entry_index])

## 判断条目是否具有可抽取的 ID、权重和数量。
func _is_eligible(entry: UFrameLootEntry) -> bool:
	return entry != null \
		and not entry.content_id.is_empty() \
		and entry.weight > 0.0 \
		and maxi(entry.min_count, entry.max_count) > 0

## 根据选中条目的数量范围生成掉落结果。
func _make_result(entry: UFrameLootEntry, rng: RandomNumberGenerator) -> Dictionary:
	var minimum := maxi(entry.min_count, 0)
	var maximum := maxi(entry.max_count, minimum)
	var count := rng.randi_range(minimum, maximum) if rng else randi_range(minimum, maximum)
	return _empty_result() if count <= 0 else {"content_id": entry.content_id, "count": count}

## 生成不包含掉落的基础结果。
func _empty_result() -> Dictionary:
	return {"content_id": StringName(), "count": 0}
#endregion
