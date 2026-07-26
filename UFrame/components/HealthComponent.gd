extends Node

'''
描述：
	生命值组件
	挂载到实体节点上，提供 hp/max_hp 管理、受伤/治疗/死亡逻辑

用法：
	1. 把 HealthComponent 挂到敌人/玩家节点下
	2. 监听信号：
	   health_component.died.connect(_on_died)
	   health_component.hp_changed.connect(_on_hp_changed)
	3. 造成伤害：
	   health_component.take_damage(20, attacker)
'''

class_name HealthComponent

#region 变量
## [b]最大生命值[/b]
@export var max_hp: int = 100

## [b]当前生命值[/b][br]
## setter 自动触发 [signal hp_changed]
var hp: int = 100

## [b]无敌时间（秒）[/b][br]
## 受伤后短暂无敌，防止连续受击
@export var invincible_duration: float = 0.0

var _invincible_timer: float = 0.0
#endregion

#region 信号
## [b]血量变化[/b][br]
## [br]参数：[br]
## [param old_value] : 变化前血量[br]
## [param new_value] : 变化后血量
signal hp_changed(old_value: int, new_value: int)

## [b]死亡[/b][br]
## [br]参数：[br]
## [param source] : 击杀者节点
signal died(source: Node)
#endregion

#region 生命周期
func _ready() -> void:
	hp = max_hp
	# 自动注册到实体，方便查找
	if get_parent().has_method("add_component"):
		get_parent().add_component("health", self)

func _process(delta: float) -> void:
	if _invincible_timer > 0:
		_invincible_timer -= delta
#endregion

#region 公开方法
## [b]造成伤害[/b][br]
## [br]参数：[br]
## [param amount] : 伤害值[br]
## [param source] : 伤害来源节点
func take_damage(amount: int, source: Node = null) -> void:
	if _invincible_timer > 0:
		return
	if amount <= 0:
		return
	if hp <= 0:
		return

	hp -= amount
	hp_changed.emit(hp + amount, hp)
	_invincible_timer = invincible_duration

	EventBus.send("entity_damaged", {
		"amount": amount,
		"source": source,
		"target": get_parent()
	})

	if hp <= 0:
		hp = 0
		died.emit(source)
		EventBus.send("entity_died", {"entity": get_parent(), "source": source})

## [b]治疗[/b][br]
## [br]参数：[br]
## [param amount] : 治疗量
func heal(amount: int) -> void:
	if amount <= 0:
		return
	var old = hp
	hp = clampi(hp + amount, 0, max_hp)
	hp_changed.emit(old, hp)

## [b]是否死亡[/b]
func is_dead() -> bool:
	return hp <= 0

## [b]设置最大血量[/b][br]
## [br]参数：[br]
## [param v] : 新的最大血量[br]
## [param fill] : 是否同时补满当前血量
func set_max_hp(v: int, fill: bool = true) -> void:
	max_hp = v
	if fill:
		hp = max_hp
#endregion
