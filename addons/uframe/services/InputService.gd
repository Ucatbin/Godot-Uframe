extends Node

## 可选输入缓冲服务
##
## 通过 [code]UFrame.input[/code] 使用，为跳跃宽限、攻击连段等操作延长输入有效窗口。
## 本服务的锁定只影响自身查询接口，不会屏蔽原生 [Input] 或节点输入回调。
## 缓冲为空时停止帧处理。
class_name UFrameInput

#region 运行时状态
## 输入缓冲：动作名 → 剩余有效时间（秒）。
var _buffer: Dictionary[String, float] = {}

## 复用过期收集数组，避免每个活跃帧创建临时数组。
var _expired: Array[String] = []

## 本服务查询接口的输入锁定状态。
var _input_locked := false
#endregion

#region 生命周期
func _ready() -> void:
	set_process(not _buffer.is_empty())

func _process(delta: float) -> void:
	# 先收集过期动作，避免遍历 Dictionary 时修改自身
	_expired.clear()
	for action in _buffer:
		_buffer[action] -= delta
		if _buffer[action] <= 0.0:
			_expired.append(action)
	for action in _expired:
		_buffer.erase(action)
	_expired.clear()
	if _buffer.is_empty():
		set_process(false)
#endregion

#region 主要方法
## 缓冲输入动作；同一动作已经存在时保留更长的剩余时间。 [br]
## 空动作名和非正数时长不会添加缓冲或启用处理。 [br][br]
## [param action] : 项目 Input Map 中的输入动作名 [br]
## [param duration] : 持续时长，单位为秒
func buffer_action(action: String, duration: float = 0.15) -> void:
	if action.is_empty() or duration <= 0.0:
		return
	_buffer[action] = maxf(_buffer.get(action, 0.0), duration)
	set_process(true)

## 消耗指定动作的输入缓冲；目标不存在时不产生副作用。 [br][br]
## [param action] : 项目 Input Map 中的输入动作名
func consume_buffer(action: String) -> void:
	_buffer.erase(action)
	if _buffer.is_empty():
		set_process(false)

## 清理全部输入缓冲。
func clear_all_buffers() -> void:
	_buffer.clear()
	set_process(false)

## 设置本服务的输入锁定；锁定时会立即清理全部缓冲。 [br][br]
## [param locked] : 是否锁定本服务的输入查询
func lock_input(locked: bool) -> void:
	if locked:
		clear_all_buffers()
	_input_locked = locked
#endregion

#region 查询方法
## 判断动作是否已缓冲；输入锁定时始终返回 [code]false[/code]。 [br][br]
## [param action] : 项目 Input Map 中的输入动作名
func is_action_buffered(action: String) -> bool:
	if _input_locked:
		return false
	return _buffer.get(action, 0.0) > 0.0

## 查询动作是否刚按下；输入锁定时返回 [code]false[/code]。 [br][br]
## [param action] : 项目 Input Map 中的输入动作名
func is_action_just_pressed(action: String) -> bool:
	if _input_locked:
		return false
	return Input.is_action_just_pressed(action)

## 查询动作是否按住；输入锁定时返回 [code]false[/code]。 [br][br]
## [param action] : 项目 Input Map 中的输入动作名
func is_action_pressed(action: String) -> bool:
	if _input_locked:
		return false
	return Input.is_action_pressed(action)

## 查询动作是否刚释放；输入锁定时返回 [code]false[/code]。 [br][br]
## [param action] : 项目 Input Map 中的输入动作名
func is_action_just_released(action: String) -> bool:
	if _input_locked:
		return false
	return Input.is_action_just_released(action)

## 获取输入方向；输入锁定时返回 [constant Vector2.ZERO]。 [br][br]
## [param negative_x] : 水平方向负向动作名 [br]
## [param positive_x] : 水平方向正向动作名 [br]
## [param negative_y] : 垂直方向负向动作名 [br]
## [param positive_y] : 垂直方向正向动作名 [br]
## [param deadzone] : 输入死区；负数时使用各动作死区的平均值
func get_vector(negative_x: String, positive_x: String, negative_y: String, positive_y: String, deadzone: float = -1.0) -> Vector2:
	if _input_locked:
		return Vector2.ZERO
	return Input.get_vector(negative_x, positive_x, negative_y, positive_y, deadzone)

## 判断本服务的输入查询是否锁定。
func is_locked() -> bool:
	return _input_locked
#endregion
