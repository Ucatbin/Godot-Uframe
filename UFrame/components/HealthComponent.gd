# ============================================================
# HealthComponent.gd  — 生命值组件
# 挂载到实体节点上，提供 hp/max_hp 和受伤/死亡信号
#
# 用法：
#   1. 把 HealthComponent 挂到敌人/玩家节点下
#   2. 监听信号：
#      health_component.died.connect(_on_died)
#      health_component.hp_changed.connect(_on_hp_changed)
#   3. 造成伤害：
#      health_component.take_damage(20, attacker)
# ============================================================

class_name HealthComponent
extends Node

## 最大生命值
@export var max_hp: int = 100

## 当前生命值（setter 自动触发信号）
var hp: int = 100

## 无敌时间（秒，受伤后短暂无敌）
@export var invincible_duration: float = 0.0

var _invincible_timer: float = 0.0

#region 信号

## 血量变化（old_value, new_value）
signal hp_changed(old_value: int, new_value: int)

## 死亡（source 是凶手）
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

## 造成伤害
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
		EventBus.emit("entity_died", {"entity": get_parent(), "source": source})

## 治疗
func heal(amount: int) -> void:
	if amount <= 0:
		return
	var old = hp
	hp = clampi(hp + amount, 0, max_hp)
	hp_changed.emit(old, hp)

## 是否死亡
func is_dead() -> bool:
	return hp <= 0

## 设置最大血量（同时补满）
func set_max_hp(v: int, fill: bool = true) -> void:
	max_hp = v
	if fill:
		hp = max_hp

#endregion
