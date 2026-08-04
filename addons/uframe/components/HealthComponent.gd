extends Node

## 可复用实体生命组件
##
## 挂到实体子节点，统一处理伤害、治疗、受伤无敌与死亡通知[br]
## 默认可以独立运行；需要属性系统时，通过 [member stat_component_path] 显式绑定 [UFrameStats]
class_name UFrameHealth

#region 信号
## [b]生命值变化[/b][br][br]
## [param old_value] : 变化前生命值[br]
## [param new_value] : 变化后生命值
signal hp_changed(old_value: int, new_value: int)

## [b]伤害生效[/b][br]
## [param amount] 是实际扣除量，不会超过受击前剩余生命值[br][br]
## [param amount] : 实际伤害[br]
## [param source] : 伤害来源节点
signal damaged(amount: int, source: Node)

## [b]治疗生效[/b][br][br]
## [param amount] : 实际恢复量
signal healed(amount: int)

## [b]死亡[/b][br]
## 生命值首次降到 [code]0[/code] 时发出[br][br]
## [param source] : 击杀者节点
signal died(source: Node)
#endregion

#region 配置
## [b]最大生命值[/b][br]
## 绑定 [UFrameStats] 后改为读取其中 [code]max_hp[/code] 的最终值
@export var max_hp: int = 100

## [b]属性组件路径[/b][br]
## 留空时不使用 [UFrameStats]
@export var stat_component_path: NodePath

## [b]受伤无敌时间（秒）[/b]
@export var invincible_duration: float = 0.0
#endregion

#region 运行时状态
## [b]当前生命值[/b]
var hp: int = 100

## [b]剩余无敌时间[/b]
var _invincible_timer: float = 0.0

## [b]属性组件缓存[/b]
var _stat_component: UFrameStats = null
#endregion

#region 生命周期
func _ready() -> void:
	if not stat_component_path.is_empty():
		_stat_component = get_node_or_null(stat_component_path) as UFrameStats
		if _stat_component == null:
			push_warning("[UFrameHealth] 找不到 UFrameStats：%s" % stat_component_path)

	hp = _get_effective_max_hp()
	set_process(false)

func _process(delta: float) -> void:
	if _invincible_timer > 0:
		_invincible_timer -= delta
		if _invincible_timer <= 0.0:
			_invincible_timer = 0.0
			set_process(false)
#endregion

#region 主要方法
## [b]承受伤害[/b][br]
## 无敌、死亡或非正数伤害不会生效；返回实际扣除量[br][br]
## [param amount] : 请求伤害值[br]
## [param source] : 伤害来源节点
func take_damage(amount: int, source: Node = null) -> int:
	if _invincible_timer > 0:
		return 0
	if amount <= 0:
		return 0
	if hp <= 0:
		return 0

	var old_hp := hp
	hp = maxi(hp - amount, 0)
	var applied := old_hp - hp
	hp_changed.emit(old_hp, hp)
	damaged.emit(applied, source)
	_invincible_timer = invincible_duration
	set_process(_invincible_timer > 0.0)

	if hp <= 0:
		died.emit(source)
	return applied

## [b]恢复生命[/b][br]
## 不会超过有效最大生命值；返回实际恢复量[br][br]
## [param amount] : 请求治疗量
func heal(amount: int) -> int:
	if amount <= 0:
		return 0
	var old := hp
	hp = clampi(hp + amount, 0, _get_effective_max_hp())
	var applied := hp - old
	if applied == 0:
		return 0
	hp_changed.emit(old, hp)
	healed.emit(applied)
	return applied

## [b]重置生命组件[/b][br]
## 清理无敌计时，适合对象池实体重新取出时调用[br]
## 可选择恢复至有效最大值，或只把当前值限制在合法范围内[br][br]
## [param fill_to_max] : 是否恢复至有效最大生命值
func reset(fill_to_max := true) -> void:
	var old_hp := hp
	_invincible_timer = 0.0
	set_process(false)
	hp = _get_effective_max_hp() if fill_to_max else clampi(hp, 0, _get_effective_max_hp())
	if hp != old_hp:
		hp_changed.emit(old_hp, hp)

## [b]补满生命值[/b][br]
## 返回实际恢复量，更适合回合重开或对象池实体复用
func refill() -> int:
	var old_hp := hp
	hp = _get_effective_max_hp()
	var applied := hp - old_hp
	if hp != old_hp:
		hp_changed.emit(old_hp, hp)
	if applied > 0:
		healed.emit(applied)
	return maxi(applied, 0)

## [b]设置最大生命值[/b][br]
## 绑定 [UFrameStats] 时修改其中 [code]max_hp[/code] 的基础值，否则修改本组件配置[br][br]
## [param v] : 新的最大生命值[br]
## [param fill] : 是否同时补满当前生命值
func set_max_hp(v: int, fill: bool = true) -> void:
	v = maxi(v, 1)
	if _stat_component:
		_stat_component.set_base_stat("max_hp", float(v))
	else:
		max_hp = v
	if fill:
		hp = _get_effective_max_hp()
	else:
		var old_hp := hp
		hp = mini(hp, _get_effective_max_hp())
		if hp != old_hp:
			hp_changed.emit(old_hp, hp)

## [b]设置属性组件[/b][br]
## 适合纯代码创建的实体；传入 [code]null[/code] 可恢复独立运行[br][br]
## [param component] : 新的属性组件[br]
## [param refill] : 是否按新的有效最大值补满生命
func set_stat_component(component: UFrameStats, refill := false) -> void:
	_stat_component = component
	if refill:
		hp = _get_effective_max_hp()
#endregion

#region 查询方法
## [b]判断是否死亡[/b]
func is_dead() -> bool:
	return hp <= 0

## [b]判断是否处于无敌状态[/b]
func is_invincible() -> bool:
	return _invincible_timer > 0
#endregion

#region 内部方法
## [b]获取有效最大生命值[/b][br]
## 绑定 [UFrameStats] 时读取 [code]max_hp[/code] 最终值，否则使用 [member max_hp]
func _get_effective_max_hp() -> int:
	if _stat_component:
		return int(_stat_component.get_stat("max_hp", float(max_hp)))
	return max_hp
#endregion
