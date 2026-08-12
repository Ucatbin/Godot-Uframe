extends UFrameBehavior

## 竞技场玩家的并行移动行为。
##
## 本节点在 arena_player.tscn 的 BehaviorManager 下静态可见，负责读取移动输入、
## 执行 CharacterBody2D 移动，并根据真实位移请求扬尘效果。
class_name ArenaPlayerMovementBehavior

#region 信号
## 按真实位移累计达到间距后发出，由关卡使用共享对象池生成扬尘。
signal dust_requested(origin: Vector2, movement_velocity: Vector2)
#endregion

#region Inspector 配置
@export_category("移动参数")
## 玩家最大移动速度。
@export var movement_speed := 270.0
## 左上角活动边界，为顶部 HUD 留出空间。
@export var minimum_position := Vector2(25, 92)
## 玩家与右下边界保持的距离。
@export var maximum_margin := Vector2(25, 25)
#endregion

#region 运行时状态
## BehaviorManager 注入实体后缓存的强类型玩家引用。
var _player: ArenaPlayer
var _traveled_distance := 0.0
#endregion

#region 行为回调
## BehaviorManager 完成实体注入后调用一次，并缓存本行为需要的强类型玩家引用。
func on_enter() -> void:
	_player = entity as ArenaPlayer
	if _player == null:
		push_warning("[ArenaPlayerMovementBehavior] 所属实体必须是 ArenaPlayer")

## Behavior 被关闭或离树时停止残留移动，并清理实体引用和累计步距。
func on_exit() -> void:
	if is_instance_valid(_player):
		_player.velocity = Vector2.ZERO
	_traveled_distance = 0.0
	_player = null

## 每个物理帧读取输入、移动玩家，并按真实位移请求扬尘反馈。
func on_physics_update(delta: float) -> void:
	if _player == null:
		return
	var direction := (
		Input.get_vector(&"demo_move_left", &"demo_move_right", &"demo_move_up", &"demo_move_down")
		if _player.controls_enabled
		else Vector2.ZERO
	)
	_player.velocity = direction * movement_speed
	var previous_position := _player.global_position
	_player.move_and_slide()
	var viewport_size := _player.get_viewport_rect().size
	_player.global_position = _player.global_position.clamp(minimum_position, viewport_size - maximum_margin)
	_update_movement_feedback(_player.global_position - previous_position, delta)
#endregion

#region 位移反馈
func _update_movement_feedback(actual_displacement: Vector2, delta: float) -> void:
	var traveled_this_frame := actual_displacement.length()
	if traveled_this_frame < 0.01:
		_traveled_distance = 0.0
		return
	_traveled_distance += traveled_this_frame
	var actual_velocity := actual_displacement / maxf(delta, 0.0001)
	var speed_ratio := clampf(actual_velocity.length() / maxf(movement_speed, 0.001), 0.0, 1.0)
	var spacing := lerpf(24.0, 12.0, speed_ratio)
	if _traveled_distance < spacing:
		return
	_traveled_distance = fmod(_traveled_distance, spacing)
	dust_requested.emit(
		_player.global_position - actual_velocity.normalized() * 13.0,
		actual_velocity
	)
#endregion
