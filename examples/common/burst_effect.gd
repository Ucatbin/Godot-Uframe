extends Node2D

## 可由 UFramePool 复用的轻量粒子爆发。
##
## 每个粒子点以 Dictionary 保存位置、速度和尺寸，由本节点统一进行物理更新和绘制。
## [method burst] 负责初始化一次爆发，寿命结束后节点会自动归还所属对象池。
## 打开 burst_effect.tscn 可以查看供多个示例复用的池化场景根。
class_name DemoBurstEffect

#region 运行时状态
## 当前爆发中的全部粒子点，每项包含 position、velocity 和 size。
var _points: Array[Dictionary] = []
## 当前爆发已经持续的时间。
var _elapsed := 0.0
## 当前爆发的总持续时间。
var _lifetime := 0.45
## 当前全部粒子共用的颜色。
var _color := Color.WHITE
## 每秒施加给粒子速度的加速度。
var _gravity := Vector2.ZERO
## 当前粒子的基础绘制半径。
var _point_size := 2.4
#endregion

#region 对象池回调
## UFramePool 回收本节点时调用，清除上一次爆发遗留的粒子。
func _on_pool_release() -> void:
	_points.clear()
	queue_redraw()
#endregion

#region 生命周期
## 在物理帧中推进粒子的位置，并在寿命结束时归还对象池。
func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _lifetime:
		_release_to_pool()
		return
	for point in _points:
		point.velocity += _gravity * delta
		point.position += point.velocity * delta
	queue_redraw()
#endregion

#region 爆发接口
## 发射一次粒子爆发。
##
## [param origin] 是爆发的世界坐标，[param direction] 是粒子的中心发射方向。
## [param amount]、[param speed] 与 [param spread_degrees] 分别控制数量、速度和方向扩散角度。
## [param inherited_velocity] 可把玩家或敌人的真实速度传递给粒子。
func burst(
	origin: Vector2,
	color: Color,
	direction: Vector2,
	amount: int,
	speed: float,
	spread_degrees: float = 55.0,
	gravity: Vector2 = Vector2(0, 90),
	lifetime: float = 0.45,
	point_size: float = 2.4,
	inherited_velocity: Vector2 = Vector2.ZERO
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
#endregion

#region 内部方法
## 将寿命结束的节点归还其父级对象池。
func _release_to_pool() -> void:
	var pool := get_parent() as UFramePool
	if pool:
		pool.release(self)
#endregion

#region 程序化绘制
## Godot 请求重绘节点时，绘制当前全部粒子点。
func _draw() -> void:
	var alpha := 1.0 - _elapsed / _lifetime
	for point in _points:
		draw_circle(point.position, point.size * (0.55 + alpha * 0.45), Color(_color, alpha))
#endregion
