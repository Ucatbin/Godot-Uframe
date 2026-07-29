extends Node

'''
描述：
	属性组件，挂载到实体节点上，管理所有 StatModifier 的叠加计算

用法：
	1. 把 StatComponent 挂到敌人/玩家节点下
	2. 装备/技能/状态效果 通过 add_modifier() 添加修正
	3. 卸下/效果结束 通过 remove_modifier() 移除
	4. 随时调用 get_stat("attack") 获取经过所有修正的最终值

示例：
	# 装备火焰剑（+50% 攻击力）
	var mod = StatModifier.new()
	mod.stat_name = "attack"
	mod.operation = StatModifier.Op.PERCENT
	mod.value = 0.5
	mod.source_name = "火焰剑"
	$StatComponent.add_modifier(mod)

	# 查询最终攻击力
	var atk = $StatComponent.get_stat("attack", 100)  # 基础 100 → 150

	# 卸下
	$StatComponent.remove_modifier(mod)  # 回到 100
'''

class_name StatComponent

#region 变量
## [b]基础属性值[/b][br]
## 实体自身的属性，不受任何修正影响
@export var base_stats: Dictionary = {}

## [b]当前生效的修正列表[/b]
var _modifiers: Array[StatModifier] = []
#endregion

#region 信号
## [b]属性变化[/b][br]
## [param stat_name] : 属性名[br]
## [param new_value] : 新值
signal stat_changed(stat_name: String, new_value: float)

## [b]修正被添加[/b]
signal modifier_added(mod: StatModifier)

## [b]修正被移除[/b]
signal modifier_removed(mod: StatModifier)
#endregion

#region 公开方法
## [b]获取最终属性值（基础值 + 全部修正叠加后）[/b][br][br]
## [param stat_name] : 属性名，如 "attack"、"speed"[br]
## [param base] : 基准值（若 base_stats 中不存在则用此值）
func get_stat(stat_name: String, base: float = 0.0) -> float:
	var current: float = base_stats.get(stat_name, base)

	# 按优先级排序（数值越小越先计算）
	var sorted := _modifiers.duplicate()
	sorted.sort_custom(func(a, b): return a.priority < b.priority)

	# 依次应用所有修正
	for mod in sorted:
		if mod.stat_name == stat_name:
			current = mod.apply(current)

	return current

## [b]获取基础值（不含任何修正）[/b]
func get_base_stat(stat_name: String) -> float:
	return base_stats.get(stat_name, 0.0)

## [b]设置基础值[/b]
func set_base_stat(stat_name: String, value: float) -> void:
	base_stats[stat_name] = value
	stat_changed.emit(stat_name, get_stat(stat_name))

## [b]添加修正[/b]
func add_modifier(mod: StatModifier) -> void:
	if mod == null:
		return
	_modifiers.append(mod)
	modifier_added.emit(mod)
	stat_changed.emit(mod.stat_name, get_stat(mod.stat_name))

## [b]移除修正[/b]
func remove_modifier(mod: StatModifier) -> void:
	var idx := _modifiers.find(mod)
	if idx != -1:
		_modifiers.remove_at(idx)
		modifier_removed.emit(mod)
		stat_changed.emit(mod.stat_name, get_stat(mod.stat_name))

## [b]移除某个来源的所有修正[/b]
func remove_by_source(source_name: String) -> void:
	var to_remove: Array[StatModifier] = []
	for mod in _modifiers:
		if mod.source_name == source_name:
			to_remove.append(mod)
	for mod in to_remove:
		remove_modifier(mod)

## [b]获取所有修正[/b]
func get_all_modifiers() -> Array[StatModifier]:
	return _modifiers.duplicate()
#endregion
