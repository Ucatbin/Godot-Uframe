extends Node

## 可选 2D 相机震动服务
##
## 通过 [code]UFrame.camera[/code] 使用，将创伤值合成为相机偏移与旋转。
## 本服务不负责跟随、缩放、慢动作或关卡取景；没有震动时停止帧处理。
## 将相机加入 [code]main_camera[/code] Group，或通过 [method set_camera] 显式绑定。
class_name UFrameCamera2D

#region 信号
## 创伤值完全衰减且相机恢复基准变换后发出。
signal shake_finished
#endregion

#region 服务配置
## 创伤值转换为实际震动强度时使用的指数。
var _trauma_power := 2.0

## 每秒衰减的创伤值。
var _decay_rate := 2.2

## 满强度时的最大位置偏移。
var _max_offset := Vector2(12.0, 9.0)

## 满强度时的最大旋转角度。
var _max_rotation_degrees := 1.5
#endregion

#region 运行时状态
## 当前接受震动结果的相机。
var _camera: Camera2D

## 绑定相机时记录的基准偏移。
var _base_offset := Vector2.ZERO

## 绑定相机时记录的基准旋转角度。
var _base_rotation_degrees := 0.0

## 当前创伤值，范围为 [code]0.0[/code] 到 [code]1.0[/code]。
var _trauma := 0.0

## 用于生成平滑震动的噪声源。
var _noise: FastNoiseLite

## 当前噪声采样时间。
var _noise_time := 0.0
#endregion

#region 生命周期
func _ready() -> void:
	set_process(false)

func _process(delta: float) -> void:
	if not is_instance_valid(_camera):
		_camera = null
		_trauma = 0.0
		set_process(false)
		return
	_trauma = maxf(_trauma - _decay_rate * delta, 0.0)
	if _trauma == 0.0:
		_reset_camera_transform()
		set_process(false)
		shake_finished.emit()
		return
	_noise_time += delta * 18.0
	var strength := pow(_trauma, _trauma_power)
	var noise_x := _noise.get_noise_1d(_noise_time)
	var noise_y := _noise.get_noise_1d(_noise_time + 100.0)
	var noise_rotation := _noise.get_noise_1d(_noise_time + 200.0)
	_camera.offset = _base_offset + Vector2(noise_x * _max_offset.x, noise_y * _max_offset.y) * strength
	_camera.rotation_degrees = _base_rotation_degrees + noise_rotation * _max_rotation_degrees * strength
#endregion

#region 主要方法
## 绑定主相机；切换前恢复旧相机，并记录新相机的稳定偏移与旋转。 [br][br]
## [param camera] : 接收震动的主相机
func set_camera(camera: Camera2D) -> void:
	if is_instance_valid(_camera) and _camera == camera:
		return
	if is_instance_valid(_camera) and _camera != camera:
		_reset_camera_transform()
	_camera = camera
	if is_instance_valid(_camera):
		_base_offset = _camera.offset
		_base_rotation_degrees = _camera.rotation_degrees

## 配置震动参数，通常在游戏启动时调用一次。 [br][br]
## [param max_offset] : 满强度时的最大位置偏移，单位为像素 [br]
## [param max_rotation_degrees] : 满强度时的最大旋转角度，单位为度 [br]
## [param decay_rate] : 每秒衰减的创伤值 [br]
## [param trauma_power] : 创伤值转换为震动强度时使用的指数
func configure_shake(
	max_offset: Vector2 = Vector2(12.0, 9.0),
	max_rotation_degrees: float = 1.5,
	decay_rate: float = 2.2,
	trauma_power: float = 2.0
) -> void:
	_max_offset = max_offset.abs()
	_max_rotation_degrees = absf(max_rotation_degrees)
	_decay_rate = maxf(decay_rate, 0.01)
	_trauma_power = maxf(trauma_power, 1.0)

## 增加震动创伤；多次冲击会累加，但不会超过 [code]1.0[/code]。 [br][br]
## [param amount] : 本次增加的创伤值；非正数不生效
func add_trauma(amount: float = 0.25) -> void:
	if amount <= 0.0:
		return
	_ensure_camera()
	if not is_instance_valid(_camera):
		return
	_ensure_noise()
	_trauma = clampf(_trauma + amount, 0.0, 1.0)
	set_process(true)

## 立即清理震动创伤并恢复相机基准变换。
func clear_trauma() -> void:
	var was_shaking := _trauma > 0.0
	_trauma = 0.0
	set_process(false)
	_reset_camera_transform()
	if was_shaking:
		shake_finished.emit()
#endregion

#region 查询方法
## 获取当前相机；没有有效绑定时尝试查找 [code]main_camera[/code] Group。
func get_camera() -> Camera2D:
	_ensure_camera()
	return _camera

## 判断当前是否有有效相机正在震动。
func is_shaking() -> bool:
	return _trauma > 0.0 and is_instance_valid(_camera)
#endregion

#region 内部方法
## 确保相机可用；没有有效绑定时按 Group 约定查找主相机。
func _ensure_camera() -> void:
	if is_instance_valid(_camera):
		return
	_camera = null
	if not is_inside_tree():
		return
	var candidate := get_tree().get_first_node_in_group(&"main_camera")
	if candidate is Camera2D:
		set_camera(candidate as Camera2D)
	elif candidate != null:
		push_warning("[UFrameCamera2D] main_camera Group 中的节点不是 Camera2D")

## 首次震动时创建噪声源。
func _ensure_noise() -> void:
	if _noise:
		return
	_noise = FastNoiseLite.new()
	_noise.seed = randi()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.08

## 恢复相机绑定时记录的基准变换。
func _reset_camera_transform() -> void:
	if not is_instance_valid(_camera):
		return
	_camera.offset = _base_offset
	_camera.rotation_degrees = _base_rotation_degrees
#endregion
