# ============================================================
# HitboxComponent.gd  — 攻击碰撞框组件
# 挂载到武器/子弹节点上，检测到对方 Hurtbox 时造成伤害
#
# 用法：
#   1. 把 HitboxComponent 挂到有 CollisionShape2D 的子节点上
#   2. 设置 damage 和 source（来源实体）
#   3. 检测到碰撞时自动调用对方 HealthComponent.take_damage()
# ============================================================

class_name HitboxComponent
extends Area2D

## 伤害值
@export var damage: int = 10

## 伤害来源（通常是玩家/敌人节点）
var source: Node = null

## 命中后是否自动销毁（子弹用）
@export var destroy_on_hit: bool = false

## 已命中的实体列表（防止一帧内重复伤害）
var _hit_entities: Array = []

#region 生命周期

func _ready() -> void:
	# 自动找 source（挂在谁下面就是谁的攻击）
	if not source:
		source = get_parent()

	# 连接碰撞信号
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _enter_tree() -> void:
	# 每帧清空命中记录（允许下一帧再次伤害）
	get_tree().process_frame.connect(_clear_hit_entities, CONNECT_ONE_SHOT)

#endregion

#region 碰撞处理

func _on_body_entered(body: Node) -> void:
	_try_hit(body)

func _on_area_entered(area: Area2D) -> void:
	_try_hit(area)

func _try_hit(target: Node) -> void:
	if not target or target in _hit_entities:
		return

	# 查找对方的 HealthComponent
	var health_comp = target.get_node_or_null("HealthComponent")
	if not health_comp:
		# 也可能 HealthComponent 在父节点上
		if target.get_parent().has_node("HealthComponent"):
			health_comp = target.get_parent().get_node("HealthComponent")

	if health_comp and health_comp.has_method("take_damage"):
		health_comp.take_damage(damage, source)
		_hit_entities.append(target)

		EventBus.emit("hit_landed", {
			"source": source,
			"target": target,
			"damage": damage
		})

		if destroy_on_hit:
			get_parent().queue_free()

#endregion

#region 内部方法

func _clear_hit_entities() -> void:
	_hit_entities.clear()
	# 下一帧继续注册
	if is_inside_tree():
		get_tree().process_frame.connect(_clear_hit_entities, CONNECT_ONE_SHOT)

#endregion
