# ============================================================
# HurtboxComponent.gd  — 受击碰撞框组件
# 挂载到敌人/玩家节点上，被攻击时转发给 HealthComponent
#
# 用法：
#   1. 把 HurtboxComponent 挂到有 CollisionShape2D 的子节点上
#   2. 它会自动找同实体下的 HealthComponent 并转发伤害
#   3. 无敌状态由 HealthComponent 统一管理，本组件不再自行维护
# ============================================================

class_name HurtboxComponent
extends Area2D

#region 生命周期
func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
#endregion

#region 碰撞处理
func _on_area_entered(area: Area2D) -> void:
	_try_receive_damage(area)

func _on_body_entered(body: Node) -> void:
	_try_receive_damage(body)

func _try_receive_damage(source: Node) -> void:
	# 查找对方的 HitboxComponent
	var hitbox = source.get_node_or_null("HitboxComponent")
	if not hitbox:
		return

	# 查找自己的 HealthComponent
	var health_comp = _find_health_component()
	if not health_comp:
		return

	# 无敌由 HealthComponent 集中管理
	if health_comp.has_method("is_invincible") and health_comp.is_invincible():
		return

	# 转发伤害
	health_comp.take_damage(hitbox.damage, hitbox.source)
#endregion

#region 内部方法
func _find_health_component() -> Node:
	var parent = get_parent()
	if parent.has_node("HealthComponent"):
		return parent.get_node("HealthComponent")
	return null
#endregion
