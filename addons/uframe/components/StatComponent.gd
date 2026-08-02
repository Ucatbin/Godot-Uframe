class_name UFrameStats
extends Node

## 实体属性组件，负责基础值、永久修正和限时修正。
## 把它挂到实体子节点，填写 Base Stats，然后使用 add_modifier() 添加装备或 Buff 效果。
## 计算结果会被缓存；只有属性或修正发生变化时才重新计算。

#region 变量
## [b]基础属性值[/b][br]
## 实体自身的属性，不受任何修正影响
@export var base_stats: Dictionary = {}

## [b]当前生效的修正列表[/b]
var _modifiers: Array[UFrameStatModifier] = []
var _cache: Dictionary[String, float] = {}
var _by_stat: Dictionary[String, Array] = {}
## 每个限时修正已经经过的秒数。只有存在限时修正时，本组件才进入帧循环。
var _elapsed: Dictionary = {}
#endregion

#region 信号
## [b]属性变化[/b][br]
## [param stat_name] : 属性名[br]
## [param new_value] : 新值
signal stat_changed(stat_name: String, new_value: float)

## [b]修正被添加[/b]
signal modifier_added(mod: UFrameStatModifier)

## [b]修正被移除[/b]
signal modifier_removed(mod: UFrameStatModifier)
#endregion

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

#region 公开方法
## [b]获取最终属性值（基础值 + 全部修正叠加后）[/b][br][br]
## [param stat_name] : 属性名，如 "attack"、"speed"[br]
## [param base] : 基准值（若 base_stats 中不存在则用此值）
func get_stat(stat_name: String, base: float = 0.0) -> float:
	if _cache.has(stat_name):
		return _cache[stat_name]
	var current: float = base_stats.get(stat_name, base)
	for mod: UFrameStatModifier in _by_stat.get(stat_name, []):
		current = mod.apply(current)
	_cache[stat_name] = current
	return current

## [b]获取基础值（不含任何修正）[/b]
func get_base_stat(stat_name: String) -> float:
	return base_stats.get(stat_name, 0.0)

## [b]设置基础值[/b]
func set_base_stat(stat_name: String, value: float) -> void:
	base_stats[stat_name] = value
	_cache.erase(stat_name)
	stat_changed.emit(stat_name, get_stat(stat_name))

## [b]添加修正[/b]
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

## [b]移除修正[/b]
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

## [b]移除某个来源的所有修正[/b]
func remove_by_source(source_name: String) -> void:
	var to_remove: Array[UFrameStatModifier] = []
	for mod in _modifiers:
		if mod.source_name == source_name:
			to_remove.append(mod)
	for mod in to_remove:
		remove_modifier(mod)

## [b]获取所有修正[/b]
func get_all_modifiers() -> Array[UFrameStatModifier]:
	return _modifiers.duplicate()
#endregion
