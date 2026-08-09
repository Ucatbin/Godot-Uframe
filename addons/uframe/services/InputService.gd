extends Node

## 可选输入缓冲服务
##
## 延长输入有效窗口时间[br]
## 适合跳跃宽限、攻击连段等操作；缓冲为空时会停止帧处理
class_name UFrameInput

#region 运行时状态
## 输入缓冲[br][br]
## 动作名 -> 剩余有效时间（秒）
var _buffer: Dictionary = {}

## 输入锁定状态
var _input_locked: bool = false
#endregion

#region 生命周期
func _ready() -> void:
	set_process(false)

func _process(delta: float) -> void:
	## 过期缓冲
	var expired: Array[String] = []
	# 更新所有缓冲并记录过期缓冲
	for action in _buffer:
		_buffer[action] -= delta
		if _buffer[action] <= 0.0:
			expired.append(action)
	for action in expired:
		_buffer.erase(action)
	if _buffer.is_empty():
		set_process(false)
#endregion

#region 主要方法
## 缓冲输入动作；同一动作已经存在时保留更长的剩余时间[br][br]
## [param action] : 输入动作名[br]
## [param duration] : 缓冲持续时间（秒）
func buffer_action(action: String, duration: float = 0.15) -> void:
	_buffer[action] = maxf(_buffer.get(action, 0.0), duration)
	set_process(true)

## 消耗输入缓冲[br][br]
## [param action] : 输入动作名
func consume_buffer(action: String) -> void:
	_buffer.erase(action)

## 清理全部输入缓冲
func clear_all_buffers() -> void:
	_buffer.clear()

## 设置输入锁定；锁定时会立即清理全部缓冲[br][br]
## [param locked] : 是否锁定输入
func lock_input(locked: bool) -> void:
	if locked:
		clear_all_buffers()
	_input_locked = locked
#endregion

#region 查询方法
## 判断动作是否已缓冲；输入锁定时始终返回 [code]false[/code][br][br]
## [param action] : 输入动作名
func is_action_buffered(action: String) -> bool:
	if _input_locked:
		return false
	return _buffer.get(action, 0.0) > 0.0

## 判断动作是否刚按下；输入锁定时返回 [code]false[/code][br][br]
## [param action] : 输入动作名
func is_action_just_pressed(action: String) -> bool:
	if _input_locked:
		return false
	return Input.is_action_just_pressed(action)

## 判断动作是否按住；输入锁定时返回 [code]false[/code][br][br]
## [param action] : 输入动作名
func is_action_pressed(action: String) -> bool:
	if _input_locked:
		return false
	return Input.is_action_pressed(action)

## 判断动作是否刚释放；输入锁定时返回 [code]false[/code][br][br]
## [param action] : 输入动作名
func is_action_just_released(action: String) -> bool:
	if _input_locked:
		return false
	return Input.is_action_just_released(action)

## 获取输入方向；输入锁定时返回 [constant Vector2.ZERO][br][br]
## [param negative_x] : 水平负方向动作[br]
## [param positive_x] : 水平正方向动作[br]
## [param negative_y] : 垂直负方向动作[br]
## [param positive_y] : 垂直正方向动作[br]
## [param deadzone] : 自定义死区，负数时使用项目设置
func get_vector(negative_x: String, positive_x: String, negative_y: String, positive_y: String, deadzone: float = -1.0) -> Vector2:
	if _input_locked:
		return Vector2.ZERO
	return Input.get_vector(negative_x, positive_x, negative_y, positive_y, deadzone)

## 判断输入是否锁定
func is_locked() -> bool:
	return _input_locked
#endregion
