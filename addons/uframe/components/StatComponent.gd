extends Node

## 实体数值属性组件
##
## 挂到实体子节点，通过 [member base_stats] 配置基础值，并使用 [method add_modifier] 添加装备或增益效果[br]
## 最终值按修正优先级计算并缓存，只有基础值或修正发生变化时才重新计算
class_name UFrameStats

#region 信号
## [b]属性值变化[/b][br]
## 基础值或修正发生变化并完成重新计算后发出[br][br]
## [param stat_name] : 属性名[br]
## [param new_value] : 新的最终值
signal stat_changed(stat_name: String, new_value: float)

## [b]修正添加完成[/b][br][br]
## [param mod] : 添加的属性修正
signal modifier_added(mod: UFrameStatModifier)

## [b]修正移除完成[/b][br][br]
## [param mod] : 移除的属性修正
signal modifier_removed(mod: UFrameStatModifier)
#endregion

#region 配置
## [b]基础属性值[/b][br]
## 实体自身的属性，不包含任何修正
@export var base_stats: Dictionary = {}
#endregion

#region 运行时状态
## [b]生效修正列表[/b]
var _modifiers: Array[UFrameStatModifier] = []

## [b]最终值缓存[/b][br][br]
## [color=cyan]映射：[/color]属性名 → 已计算的最终值。
var _cache: Dictionary[String, float] = {}

## [b]按属性分组的修正[/b][br][br]
## [color=cyan]映射：[/color]属性名 → 按优先级排列的修正数组。
var _by_stat: Dictionary[String, Array] = {}

## [b]限时修正计时[/b][br]
## 记录每项限时修正已经生效的秒数；没有限时修正时停止帧处理
var _elapsed: Dictionary = {}
#endregion

#region 生命周期
func _ready() -> void:
	set_process(false)

func _process(delta: float) -> void:
	var expired: Array[UFrameStatModifier] = []
	for mod: UFrameStatModifier in _elapsed:
		_elapsed[mod] += delta
		if mod.is_expired(_elapsed[mod]):
			expired.append(mod)
	for mod in expired:
		remove_modifier(mod)
	if _elapsed.is_empty():
		set_process(false)
#endregion

#region 主要方法
## [b]设置基础属性值[/b][br]
## 清除对应缓存并发出 [signal stat_changed][br][br]
## [param stat_name] : 属性名[br]
## [param value] : 新的基础值
func set_base_stat(stat_name: String, value: float) -> void:
	base_stats[stat_name] = value
	_cache.erase(stat_name)
	stat_changed.emit(stat_name, get_stat(stat_name))

## [b]添加属性修正[/b][br]
## 限时修正会自动开始计时；空值会被忽略[br][br]
## [param mod] : 需要添加的属性修正
func add_modifier(mod: UFrameStatModifier) -> void:
	if mod == null:
		return
	_modifiers.append(mod)
	if mod.duration >= 0.0:
		_elapsed[mod] = 0.0
		set_process(true)
	var bucket: Array = _by_stat.get_or_add(mod.stat_name, [])
	bucket.append(mod)
	bucket.sort_custom(func(a: UFrameStatModifier, b: UFrameStatModifier) -> bool: return a.priority < b.priority)
	_cache.erase(mod.stat_name)
	modifier_added.emit(mod)
	stat_changed.emit(mod.stat_name, get_stat(mod.stat_name))

## [b]移除属性修正[/b][br]
## 不在当前列表中的修正会被忽略[br][br]
## [param mod] : 需要移除的属性修正
func remove_modifier(mod: UFrameStatModifier) -> void:
	var idx := _modifiers.find(mod)
	if idx != -1:
		_modifiers.remove_at(idx)
		_elapsed.erase(mod)
		var bucket: Array = _by_stat.get(mod.stat_name, [])
		bucket.erase(mod)
		if bucket.is_empty():
			_by_stat.erase(mod.stat_name)
		_cache.erase(mod.stat_name)
		modifier_removed.emit(mod)
		stat_changed.emit(mod.stat_name, get_stat(mod.stat_name))

## [b]按来源移除修正[/b][br][br]
## [param source_name] : 需要清理的修正来源名
func remove_by_source(source_name: String) -> void:
	var to_remove: Array[UFrameStatModifier] = []
	for mod in _modifiers:
		if mod.source_name == source_name:
			to_remove.append(mod)
	for mod in to_remove:
		remove_modifier(mod)
#endregion

#region 查询方法
## [b]获取最终属性值[/b][br]
## 按优先级应用全部修正；基础属性不存在时使用 [param base][br][br]
## [param stat_name] : 属性名[br]
## [param base] : 属性不存在时使用的基础值
func get_stat(stat_name: String, base: float = 0.0) -> float:
	if _cache.has(stat_name):
		return _cache[stat_name]
	var current: float = base_stats.get(stat_name, base)
	for mod: UFrameStatModifier in _by_stat.get(stat_name, []):
		current = mod.apply(current)
	_cache[stat_name] = current
	return current

## [b]获取基础属性值[/b][br]
## 不包含任何修正；属性不存在时返回 [code]0.0[/code][br][br]
## [param stat_name] : 属性名
func get_base_stat(stat_name: String) -> float:
	return base_stats.get(stat_name, 0.0)

## [b]获取全部属性修正[/b][br]
## 返回新的数组，不会暴露内部列表
func get_all_modifiers() -> Array[UFrameStatModifier]:
	return _modifiers.duplicate()
#endregion
