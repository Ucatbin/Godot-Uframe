class_name ArenaBullet
extends Node2D

## 对象池子弹实体。
##
## 移动和寿命属于实体根节点，伤害数据与碰撞判定由场景中的
## HitboxComponent 子节点负责，体现“实体由组件组合”的结构。

signal hit_confirmed(target: Node, applied_damage: int)

const SPEED := 560.0

@onready var hitbox: UFrameHitbox2D = $HitboxComponent

var direction := Vector2.RIGHT
var _release_queued := false

## 从指定位置沿方向发射，并把攻击者交给 Hitbox 用于 Team 判断。
func launch(origin: Vector2, new_direction: Vector2, attack_owner: Node) -> void:
	global_position = origin
	direction = new_direction.normalized()
	hitbox.source = attack_owner
	hitbox.reset_hits()
	_release_queued = false
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	global_position += direction * SPEED * delta
	if not get_viewport_rect().grow(80).has_point(global_position):
		_release_to_pool()

func _on_hitbox_component_hit_confirmed(target: Node, applied_damage: int) -> void:
	if _release_queued:
		return
	_release_queued = true
	hit_confirmed.emit(target, applied_damage)
	# 碰撞回调中不直接改变物理对象状态，延迟到安全时机归还。
	call_deferred("_release_to_pool")

func _on_pool_acquire() -> void:
	direction = Vector2.RIGHT
	_release_queued = false
	hitbox.reset_hits()

func _on_pool_release() -> void:
	direction = Vector2.RIGHT
	_release_queued = false
	hitbox.source = null
	hitbox.reset_hits()

func _release_to_pool() -> void:
	var pool := get_parent() as UFramePool
	if pool:
		pool.release(self)

func _draw() -> void:
	# 节点朝向已经与速度一致，拖尾始终画在局部 -X 方向。
	draw_line(Vector2(-18, 0), Vector2(-4, 0), Color(Color("#ffca70"), 0.28), 5.0)
	draw_circle(Vector2.ZERO, 7.0, Color(Color("#ffca70"), 0.18))
	draw_circle(Vector2.ZERO, 4.0, Color("#fff4bd"))
