class_name UFrameLootTable
extends Resource

## 纯配置的加权掉落表。
##
## LootTable 不保存“连续未掉落次数”，因此同一个 .tres 可以安全地被多个敌人或玩家共享。[br]
## 调用者把上次结果中的 miss_count 传给下一次 roll()，即可获得独立保底状态。
## [codeblock]
## var result := table.roll(miss_count)
## miss_count = result.miss_count
## if result.count > 0:
##     inventory.add_item(result.content_id, result.count)
## [/codeblock]

## 可被选中的掉落条目。
@export var entries: Array[UFrameLootEntry] = []
## “什么都不掉落”的额外权重。0 表示每次都尝试选择有效条目。
@export_range(0.0, 1000000.0) var no_drop_weight := 0.0
## 连续未掉落多少次后触发保底。0 表示关闭保底。
@export_range(0, 1000000) var pity_count := 0
## 保底时使用的 entries 下标。下标或条目无效时不会触发保底。
@export var pity_entry_index := -1

## 抽取一次掉落。
##
## miss_count 是该调用者此前连续未掉落的次数；返回值固定包含 content_id、count、[br]
## miss_count 和 pity_triggered。传入 RandomNumberGenerator 可获得可复现结果。
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

## 连续抽取多次并合并相同内容。返回 drops 数组和下一次应继续使用的 miss_count。
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

## 获取所有不重复的有效内容 ID，可用于进入关卡前预加载资源。
func get_all_content_ids() -> Array[StringName]:
	var unique: Dictionary[StringName, bool] = {}
	for entry in entries:
		if _is_eligible(entry):
			unique[entry.content_id] = true
	return unique.keys()

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

func _should_trigger_pity(miss_count: int) -> bool:
	return pity_count > 0 \
		and miss_count >= pity_count \
		and pity_entry_index >= 0 \
		and pity_entry_index < entries.size() \
		and _is_eligible(entries[pity_entry_index])

func _is_eligible(entry: UFrameLootEntry) -> bool:
	return entry != null \
		and not entry.content_id.is_empty() \
		and entry.weight > 0.0 \
		and maxi(entry.min_count, entry.max_count) > 0

func _make_result(entry: UFrameLootEntry, rng: RandomNumberGenerator) -> Dictionary:
	var minimum := maxi(entry.min_count, 0)
	var maximum := maxi(entry.max_count, minimum)
	var count := rng.randi_range(minimum, maximum) if rng else randi_range(minimum, maximum)
	return _empty_result() if count <= 0 else {"content_id": entry.content_id, "count": count}

func _empty_result() -> Dictionary:
	return {"content_id": StringName(), "count": 0}
