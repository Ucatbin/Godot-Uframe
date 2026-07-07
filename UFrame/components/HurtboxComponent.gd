# ============================================================
# HurtboxComponent.gd  — 受击碰撞框组件
# 挂载到敌人/玩家节点上，被攻击时转发给 HealthComponent
#
# 用法：
#   1. 把 HurtboxComponent 挂到有 CollisionShape2D 的子节点上
#   2. 它会自动找同实体下的 HealthComponent 并转发伤害
# ============================================================

class_name HurtboxComponent
extends Area2D

## 受伤无敌时间（秒）
@export var invincible_duration: float = 0.0

var _invincible_timer: float = 0.0

#region 生命周期

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if _invincible_timer > 0:
		_invincible_timer -= delta

#endregion

#region 碰撞处理

func _on_area_entered(area: Area2D) -> void:
	_try_receive_damage(area)

func _on_body_entered(body: Node) -> void:
	_try_receive_damage(body)

func _try_receive_damage(source: Node) -> void:
	if _invincible_timer > 0:
		return

	# 查找对方的 HitboxComponent
	var hitbox = source.get_node_or_null("HitboxComponent")
	if not hitbox:
		return

	# 查找自己的 HealthComponent
	var health_comp = _find_health_component()
	if not health_comp:
		return

	health_comp.take_damage(hitbox.damage, hitbox.source)
	_invincible_timer = invincible_duration

#endregion

#region 内部方法

func _find_health_component() -> Node:
	# 先找自己节点下有没有
	if has_node("../HealthComponent"):
		return get_parent().get_node("HealthComponent")
	# 再找父节点下
	var parent = get_parent()
	if parent.has_node("HealthComponent"):
		return parent.get_node("HealthComponent")
	return null

#endregion
