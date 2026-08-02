extends Node

## 可复用生命值组件。挂到实体的子 Node 上，负责受伤、治疗、无敌时间和死亡通知。
## 默认没有外部依赖；需要属性系统时，通过 Stat Component Path 显式指定 UFrameStats。
class_name UFrameHealth

#region 变量
## [b]最大生命值[/b][br]
## 配置 Stat Component Path 后，会读取该组件中的 max_hp 最终值。
@export var max_hp: int = 100

## 可选 UFrameStats 路径。留空表示 UFrameHealth 完全独立运行。
@export var stat_component_path: NodePath

## [b]当前生命值[/b]
var hp: int = 100

## [b]无敌时间（秒）[/b][br]
## 受伤后短暂无敌，防止连续受击
@export var invincible_duration: float = 0.0

var _invincible_timer: float = 0.0

## 显式解析后的属性组件缓存。
var _stat_component: UFrameStats = null
#endregion

#region 信号
## [b]血量变化[/b][br]
## [br]参数：[br]
## [param old_value] : 变化前血量[br]
## [param new_value] : 变化后血量
signal hp_changed(old_value: int, new_value: int)

## 成功受到伤害时发出。amount 是实际扣除量，不会大于剩余生命。
signal damaged(amount: int, source: Node)

## 成功恢复生命时发出。amount 是实际恢复量。
signal healed(amount: int)

## [b]死亡[/b][br]
## [br]参数：[br]
## [param source] : 击杀者节点
signal died(source: Node)
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

#region 公开方法
## [b]造成伤害[/b][br]
## [br]参数：[br]
## [param amount] : 伤害值[br]
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

## [b]治疗[/b][br]
## [br]参数：[br]
## [param amount] : 治疗量
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

## [b]是否死亡[/b]
func is_dead() -> bool:
	return hp <= 0

## [b]是否处于无敌状态[/b]
func is_invincible() -> bool:
	return _invincible_timer > 0

## [b]重置生命组件[/b][br]
## 清除死亡状态和无敌计时；对象池重新取出实体时应调用本方法。[br]
## [param fill_to_max] 为 true 时恢复至有效最大生命值，为 false 时只把当前值限制到合法范围。
func reset(fill_to_max := true) -> void:
	var old_hp := hp
	_invincible_timer = 0.0
	set_process(false)
	hp = _get_effective_max_hp() if fill_to_max else clampi(hp, 0, _get_effective_max_hp())
	if hp != old_hp:
		hp_changed.emit(old_hp, hp)

## 恢复至有效最大生命值，并返回实际恢复量。
## 普通治疗使用 heal()；本方法更适合回合重开或对象池实体复用。
func refill() -> int:
	var old_hp := hp
	hp = _get_effective_max_hp()
	var applied := hp - old_hp
	if hp != old_hp:
		hp_changed.emit(old_hp, hp)
	if applied > 0:
		healed.emit(applied)
	return maxi(applied, 0)

## [b]设置最大血量[/b][br]
## [br]参数：[br]
## [param v] : 新的最大血量[br]
## [param fill] : 是否同时补满当前血量
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

## 运行时显式注入或移除 UFrameStats，适合纯代码创建的实体。
func set_stat_component(component: UFrameStats, refill := false) -> void:
	_stat_component = component
	if refill:
		hp = _get_effective_max_hp()

## [b]获取有效最大血量[/b][br]
## 有 UFrameStats → 从 stat "max_hp" 读取（含装备加成）[br]
## 无 UFrameStats → 使用 @export max_hp
func _get_effective_max_hp() -> int:
	if _stat_component:
		return int(_stat_component.get_stat("max_hp", float(max_hp)))
	return max_hp
#endregion
