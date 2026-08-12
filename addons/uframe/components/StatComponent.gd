extends Node

## 实体数值属性组件。
##
## 负责基础属性、属性修正、最终值缓存，以及运行时限时修正的到期移除。
## 不负责装备、Buff 来源或存档格式；调用方创建 [UFrameStatModifier] 并决定何时添加和持久化。
## 当前示例未静态挂载本组件；宿主项目应把它作为实体直属子节点，并通过 Inspector 配置 [member base_stats]。
class_name UFrameStats

#region 信号
## 基础值或修正发生变化并完成重新计算后发出。
## [param stat_name] 是属性名，[param new_value] 是新的最终值。
signal stat_changed(stat_name: String, new_value: float)

## 属性修正完成添加后发出。[param mod] 是本次添加的修正。
signal modifier_added(mod: UFrameStatModifier)

## 属性修正完成移除后发出。[param mod] 是本次移除的修正。
signal modifier_removed(mod: UFrameStatModifier)
#endregion

#region Inspector 配置
## 实体自身的基础属性映射，不包含任何修正。
@export var base_stats: Dictionary = {}
#endregion

#region 运行时状态
## 当前全部生效修正。
var _modifiers: Array[UFrameStatModifier] = []

## 以 Resource 实例为键的成员集合，用于常数时间拒绝重复添加和确认移除目标。
var _modifier_lookup: Dictionary = {}

## 属性名到已计算最终值的缓存。
var _cache: Dictionary[String, float] = {}

## 属性名到按优先级排列修正数组的映射。
var _by_stat: Dictionary[String, Array] = {}

## 每项限时修正已经生效的秒数；没有限时修正时停止普通帧处理。
var _elapsed: Dictionary = {}

## 帧间复用的到期收集数组，避免每个活跃帧创建临时容器。
var _expired_buffer: Array[UFrameStatModifier] = []

## 批量生命周期信号正在同步发送时为 true，防止监听器让同一事务发生逆序重入。
var _notifying_modifier_transaction := false
#endregion

#region 生命周期
## 只有存在限时修正时才启用帧处理。
## 修正可能在节点入树前加入，因此不能在这里无条件关闭处理。
func _ready() -> void:
	set_process(not _elapsed.is_empty())

func _process(delta: float) -> void:
	_expired_buffer.clear()
	for mod: UFrameStatModifier in _elapsed:
		_elapsed[mod] += delta
		if mod.is_expired(_elapsed[mod]):
			_expired_buffer.append(mod)
	if not _expired_buffer.is_empty():
		remove_modifiers(_expired_buffer)
		# 及时释放已过期 Resource 引用，同时保留数组容量供下次复用
		_expired_buffer.clear()
	elif _elapsed.is_empty():
		set_process(false)
#endregion

#region 属性操作
## 把 [param stat_name] 的基础值设为 [param value]，清除对应缓存并发出 [signal stat_changed]。
func set_base_stat(stat_name: String, value: float) -> void:
	base_stats[stat_name] = value
	_cache.erase(stat_name)
	stat_changed.emit(stat_name, get_stat(stat_name))

## 添加 [param mod]，按优先级重排其属性分组，并刷新对应最终值。
## 空值和已经生效的同一 Resource 实例会被拒绝；成功时返回 [code]true[/code]。
## 限时修正会自动开始计时并启用普通帧处理。
func add_modifier(mod: UFrameStatModifier) -> bool:
	if not _can_mutate_modifiers():
		return false
	if not _can_add_modifier(mod):
		return false
	if _store_modifier(mod):
		set_process(true)
	_sort_and_invalidate_stat(mod.stat_name)
	_notifying_modifier_transaction = true
	modifier_added.emit(mod)
	stat_changed.emit(mod.stat_name, get_stat(mod.stat_name))
	_notifying_modifier_transaction = false
	return true

## 批量添加 [param modifiers]，返回实际加入的修正数量。
## 空值、已生效实例和参数内的重复实例会被跳过；每个受影响属性只排序、重算并通知一次。
func add_modifiers(modifiers: Array[UFrameStatModifier]) -> int:
	if not _can_mutate_modifiers():
		return 0
	var added: Array[UFrameStatModifier] = []
	var affected_stats: Array[String] = []
	var affected_lookup: Dictionary = {}
	var added_timed_modifier := false
	for mod: UFrameStatModifier in modifiers:
		if not _can_add_modifier(mod):
			continue
		if _store_modifier(mod):
			added_timed_modifier = true
		added.append(mod)
		if not affected_lookup.has(mod.stat_name):
			affected_lookup[mod.stat_name] = true
			affected_stats.append(mod.stat_name)
	if added.is_empty():
		return 0
	if added_timed_modifier:
		set_process(true)
	for stat_name: String in affected_stats:
		_sort_and_invalidate_stat(stat_name)
	_notifying_modifier_transaction = true
	for mod: UFrameStatModifier in added:
		modifier_added.emit(mod)
	for stat_name: String in affected_stats:
		stat_changed.emit(stat_name, get_stat(stat_name))
	_notifying_modifier_transaction = false
	return added.size()

## 移除 [param mod] 并刷新对应最终值；成功时返回 [code]true[/code]。
## 空值或不在当前列表中的修正不会改变组件状态，并返回 [code]false[/code]。
func remove_modifier(mod: UFrameStatModifier) -> bool:
	if not _can_mutate_modifiers():
		return false
	if mod == null or not _modifier_lookup.has(mod):
		return false
	_erase_modifier(mod)
	_cache.erase(mod.stat_name)
	if _elapsed.is_empty():
		set_process(false)
	_notifying_modifier_transaction = true
	modifier_removed.emit(mod)
	stat_changed.emit(mod.stat_name, get_stat(mod.stat_name))
	_notifying_modifier_transaction = false
	return true

## 批量移除 [param modifiers]，返回实际移除的修正数量。
## 每个实例至多移除一次，每个受影响属性只失效、重算并通知一次。
func remove_modifiers(modifiers: Array[UFrameStatModifier]) -> int:
	if not _can_mutate_modifiers():
		return 0
	var removed: Array[UFrameStatModifier] = []
	var removal_lookup: Dictionary = {}
	var affected_stats: Array[String] = []
	var affected_lookup: Dictionary = {}
	for mod: UFrameStatModifier in modifiers:
		if mod == null or removal_lookup.has(mod) or not _modifier_lookup.has(mod):
			continue
		removed.append(mod)
		removal_lookup[mod] = true
		if not affected_lookup.has(mod.stat_name):
			affected_lookup[mod.stat_name] = true
			affected_stats.append(mod.stat_name)
	if removed.is_empty():
		return 0

	_compact_modifier_array(_modifiers, removal_lookup)
	for mod: UFrameStatModifier in removed:
		_modifier_lookup.erase(mod)
		_elapsed.erase(mod)
	for stat_name: String in affected_stats:
		var bucket: Array = _by_stat[stat_name]
		_compact_modifier_array(bucket, removal_lookup)
		if bucket.is_empty():
			_by_stat.erase(stat_name)
		_cache.erase(stat_name)
	if _elapsed.is_empty():
		set_process(false)
	_notifying_modifier_transaction = true
	for mod: UFrameStatModifier in removed:
		modifier_removed.emit(mod)
	for stat_name: String in affected_stats:
		stat_changed.emit(stat_name, get_stat(stat_name))
	_notifying_modifier_transaction = false
	return removed.size()

## 移除全部来源名等于 [param source_name] 的修正。
func remove_by_source(source_name: String) -> void:
	if not _can_mutate_modifiers():
		return
	var to_remove: Array[UFrameStatModifier] = []
	for mod: UFrameStatModifier in _modifiers:
		if mod.source_name == source_name:
			to_remove.append(mod)
	remove_modifiers(to_remove)
#endregion

#region 属性查询
## 获取 [param stat_name] 的最终值；基础属性不存在时使用 [param base]。
## 第一次查询按优先级应用全部修正并缓存，后续查询直接读取缓存。
func get_stat(stat_name: String, base: float = 0.0) -> float:
	if _cache.has(stat_name):
		return _cache[stat_name]
	var current: float = base_stats.get(stat_name, base)
	for mod: UFrameStatModifier in _by_stat.get(stat_name, []):
		current = mod.apply(current)
	_cache[stat_name] = current
	return current

## 获取 [param stat_name] 的基础值，不包含修正；不存在时返回 [code]0.0[/code]。
func get_base_stat(stat_name: String) -> float:
	return base_stats.get(stat_name, 0.0)

## 获取全部属性修正的数组副本，不暴露内部列表。
func get_all_modifiers() -> Array[UFrameStatModifier]:
	return _modifiers.duplicate()
#endregion

#region 内部方法
## 判断当前是否允许修改修正集合；同步信号监听器需要使用 call_deferred() 延后同组件修改。
func _can_mutate_modifiers() -> bool:
	if not _notifying_modifier_transaction:
		return true
	push_warning("[UFrameStats] 修正事务通知期间不能同步增删同一组件的修正；请使用 call_deferred()")
	return false

## 检查修正能否加入；重复实例会给出明确诊断，避免限时计时状态发生歧义。
func _can_add_modifier(mod: UFrameStatModifier) -> bool:
	if mod == null:
		return false
	if _modifier_lookup.has(mod):
		push_warning("[UFrameStats] 同一个 UFrameStatModifier 实例不能重复添加；需要独立层数时请先 duplicate()")
		return false
	return true

## 写入一项已经通过校验的修正；返回它是否需要帧计时。
func _store_modifier(mod: UFrameStatModifier) -> bool:
	_modifiers.append(mod)
	_modifier_lookup[mod] = true
	var bucket: Array
	if _by_stat.has(mod.stat_name):
		bucket = _by_stat[mod.stat_name]
	else:
		bucket = []
		_by_stat[mod.stat_name] = bucket
	bucket.append(mod)
	if mod.duration < 0.0:
		return false
	_elapsed[mod] = 0.0
	return true

## 从全部索引中移除一项已经确认存在的修正。
func _erase_modifier(mod: UFrameStatModifier) -> void:
	var modifier_index := _modifiers.find(mod)
	_modifiers.remove_at(modifier_index)
	_modifier_lookup.erase(mod)
	_elapsed.erase(mod)
	var bucket: Array = _by_stat[mod.stat_name]
	var bucket_index := bucket.find(mod)
	bucket.remove_at(bucket_index)
	if bucket.is_empty():
		_by_stat.erase(mod.stat_name)

## 重排一个属性的修正并清除缓存；调用方随后统一重算和发送变化信号。
func _sort_and_invalidate_stat(stat_name: String) -> void:
	var bucket: Array = _by_stat[stat_name]
	bucket.sort_custom(_has_lower_priority)
	_cache.erase(stat_name)

## 按优先级升序排列修正，确保更小的优先级先参与计算。
func _has_lower_priority(a: UFrameStatModifier, b: UFrameStatModifier) -> bool:
	return a.priority < b.priority

## 原地压缩 [param modifiers]，一次扫描移除 [param removal_lookup] 中的全部实例。
func _compact_modifier_array(modifiers: Array, removal_lookup: Dictionary) -> void:
	var write_index := 0
	var original_size := modifiers.size()
	for read_index in original_size:
		var mod: UFrameStatModifier = modifiers[read_index]
		if removal_lookup.has(mod):
			continue
		if write_index != read_index:
			modifiers[write_index] = mod
		write_index += 1
	modifiers.resize(write_index)
#endregion
