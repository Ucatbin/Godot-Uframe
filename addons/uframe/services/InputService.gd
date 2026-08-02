class_name UFrameInput
extends Node

## 可选输入缓冲服务，通过 UFrame.input 使用。
## buffer_action() 会让一次输入在短时间内保持可消费，适合跳跃宽限、攻击连段等操作。
## 缓冲为空时自动停止帧处理，因此启用模块但不使用缓冲几乎没有持续开销。

func _ready() -> void:
	set_process(false)

#region 变量
## [b]输入缓冲：{ action_name: remaining_time }[/b]
var _buffer: Dictionary = {}

## [b]已锁定输入[/b]
var _input_locked: bool = false

#endregion

#region 缓冲
## [b]缓冲一个动作（在 duration 秒内持续有效）[/b]
func buffer_action(action: String, duration: float = 0.15) -> void:
	_buffer[action] = maxf(_buffer.get(action, 0.0), duration)
	set_process(true)

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
	if _buffer.is_empty():
		set_process(false)
#endregion
