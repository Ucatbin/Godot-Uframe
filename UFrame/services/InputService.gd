extends Node

'''
描述：
	输入缓冲/管理服务（Autoload 单例）
	提供输入缓冲、连击检测、输入锁定等通用输入功能

用法：
	# 输入缓冲（按下后 N 秒内仍然有效，适合格斗游戏）
	InputService.buffer_action("attack", 0.15)
	if InputService.is_action_buffered("attack"):
		perform_attack()

	# 检查是否刚刚按下（仅触发一帧）
	if InputService.is_action_just_pressed("jump"):
		jump()

	# 锁定玩家输入
	InputService.lock_input(true)
'''

class_name InputService

#region 变量
## [b]输入缓冲：{ action_name: remaining_time }[/b]
var _buffer: Dictionary = {}

## [b]已锁定输入[/b]
var _input_locked: bool = false

## [b]上一帧的动作状态（用于 just_pressed）[/b]
var _prev_action_states: Dictionary = {}
#endregion

#region 缓冲
## [b]缓冲一个动作（在 duration 秒内持续有效）[/b]
func buffer_action(action: String, duration: float = 0.15) -> void:
	_buffer[action] = maxf(_buffer.get(action, 0.0), duration)

## [b]检查某动作是否在缓冲窗口内[/b]
func is_action_buffered(action: String) -> bool:
	if _input_locked:
		return false
	return _buffer.get(action, 0.0) > 0.0

## [b]消耗（清除）一个缓冲[/b]
func consume_buffer(action: String) -> void:
	_buffer.erase(action)

## [b]清除所有缓冲[/b]
func clear_all_buffers() -> void:
	_buffer.clear()
#endregion

#region 输入检查（封装 Input 单例）
## [b]是否刚刚按下（真·单帧触发，不受锁定影响）[/b]
func is_action_just_pressed(action: String) -> bool:
	if _input_locked:
		return false
	return Input.is_action_just_pressed(action)

## [b]是否按住[/b]
func is_action_pressed(action: String) -> bool:
	if _input_locked:
		return false
	return Input.is_action_pressed(action)

## [b]是否释放[/b]
func is_action_just_released(action: String) -> bool:
	if _input_locked:
		return false
	return Input.is_action_just_released(action)

## [b]获取输入轴值（方向）[/b]
func get_vector(negative_x: String, positive_x: String, negative_y: String, positive_y: String, deadzone: float = -1.0) -> Vector2:
	if _input_locked:
		return Vector2.ZERO
	return Input.get_vector(negative_x, positive_x, negative_y, positive_y, deadzone)
#endregion

#region 锁定
## [b]锁定/解锁玩家输入[/b]
func lock_input(locked: bool) -> void:
	if locked:
		clear_all_buffers()
	_input_locked = locked

## [b]是否已锁定[/b]
func is_locked() -> bool:
	return _input_locked
#endregion

#region 生命周期
func _process(delta: float) -> void:
	# 缓冲时间递减
	var expired: Array[String] = []
	for action in _buffer:
		_buffer[action] -= delta
		if _buffer[action] <= 0.0:
			expired.append(action)
	for action in expired:
		_buffer.erase(action)
#endregion
