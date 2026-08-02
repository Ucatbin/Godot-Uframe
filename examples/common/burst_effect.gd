class_name DemoBurstEffect
extends Node2D

## 可由 UFramePool 复用的轻量粒子爆发。每个点都遵循速度、方向、重力和寿命。

var _points: Array[Dictionary] = []
var _elapsed := 0.0
var _lifetime := 0.45
var _color := Color.WHITE
var _gravity := Vector2.ZERO
var _point_size := 2.4

## 发射一次粒子爆发。inherited_velocity 可把玩家/敌人的真实速度传给粒子。
func burst(
	origin: Vector2,
	color: Color,
	direction: Vector2,
	amount: int,
	speed: float,
	spread_degrees := 55.0,
	gravity := Vector2(0, 90),
	lifetime := 0.45,
	point_size := 2.4,
	inherited_velocity := Vector2.ZERO
) -> void:
	global_position = origin
	_elapsed = 0.0
	_lifetime = maxf(lifetime, 0.05)
	_color = color
	_gravity = gravity
	_point_size = point_size
	_points.clear()
	var base_direction := direction.normalized() if not direction.is_zero_approx() else Vector2.UP
	for index in maxi(amount, 1):
		var angle := deg_to_rad(randf_range(-spread_degrees, spread_degrees))
		var velocity := base_direction.rotated(angle) * randf_range(speed * 0.55, speed)
		_points.append({
			"position": Vector2.ZERO,
			"velocity": velocity + inherited_velocity,
			"size": randf_range(_point_size * 0.65, _point_size * 1.35),
		})
	queue_redraw()

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _lifetime:
		_release_to_pool()
		return
	for point in _points:
		point.velocity += _gravity * delta
		point.position += point.velocity * delta
	queue_redraw()

func _draw() -> void:
	var alpha := 1.0 - _elapsed / _lifetime
	for point in _points:
		draw_circle(point.position, point.size * (0.55 + alpha * 0.45), Color(_color, alpha))

func _on_pool_release() -> void:
	_points.clear()
	queue_redraw()

func _release_to_pool() -> void:
	var pool := get_parent() as UFramePool
	if pool:
		pool.release(self)
