extends Node2D

## 对象池子弹实体。
##
## 打开 arena_bullet.tscn 可以看到实体根与 HitboxComponent 的静态组合。
## 本脚本只负责移动、离屏归还和命中反馈；伤害数据与碰撞判定由 HitboxComponent 负责。
class_name ArenaBullet

#region 常量与信号
const SPEED := 560.0

## Hitbox 确认实际伤害后发出，供关卡播放命中反馈。
signal hit_confirmed(target: Node, applied_damage: int)
#endregion

#region 依赖与状态
## 场景中静态挂载的伤害组件。
@onready var hitbox: UFrameHitbox2D = $HitboxComponent

## 本轮发射使用的单位方向。
var direction := Vector2.RIGHT
## 命中后等待安全归还时保持 true，防止重复确认命中。
var _release_queued := false
#endregion

#region 对象池回调
## Pool 取出实例时清理上一轮命中状态。
func _on_pool_acquire() -> void:
	direction = Vector2.RIGHT
	_release_queued = false
	hitbox.reset_hits()

## Pool 归还实例时清除攻击者和命中记录，避免污染下一次发射。
func _on_pool_release() -> void:
	direction = Vector2.RIGHT
	_release_queued = false
	hitbox.source = null
	hitbox.reset_hits()
#endregion

#region 生命周期
## 在物理帧推进子弹，并在离开视口预算范围后归还对象池。
func _physics_process(delta: float) -> void:
	global_position += direction * SPEED * delta
	if not get_viewport_rect().grow(80).has_point(global_position):
		_release_to_pool()
#endregion

#region 发射接口
## 从指定位置沿方向发射，并把攻击者交给 Hitbox 用于 Team 判断。
func launch(origin: Vector2, new_direction: Vector2, attack_owner: Node) -> void:
	global_position = origin
	direction = new_direction.normalized()
	hitbox.source = attack_owner
	hitbox.reset_hits()
	_release_queued = false
	rotation = direction.angle()
#endregion

#region 组件信号
## Hitbox 确认命中后转发反馈，并延迟到物理回调结束后安全归还。
func _on_hitbox_component_hit_confirmed(target: Node, applied_damage: int) -> void:
	if _release_queued:
		return
	_release_queued = true
	hit_confirmed.emit(target, applied_damage)
	# 碰撞回调中不直接改变物理对象状态，延迟到安全时机归还。
	call_deferred("_release_to_pool")
#endregion

#region 内部方法
func _release_to_pool() -> void:
	var pool := get_parent() as UFramePool
	if pool:
		pool.release(self)
#endregion

#region 程序化绘制
func _draw() -> void:
	# 节点朝向已经与速度一致，拖尾始终画在局部 -X 方向。
	draw_line(Vector2(-18, 0), Vector2(-4, 0), Color(Color("#ffca70"), 0.28), 5.0)
	draw_circle(Vector2.ZERO, 7.0, Color(Color("#ffca70"), 0.18))
	draw_circle(Vector2.ZERO, 4.0, Color("#fff4bd"))
#endregion
