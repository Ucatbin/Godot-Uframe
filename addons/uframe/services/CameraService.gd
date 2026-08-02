class_name UFrameCamera2D
extends Node

## 可选的 Camera2D 震动服务，通过 UFrame.camera 使用。
##
## 本服务只负责把 trauma 合成为相机 offset/rotation，不负责跟随、缩放、慢动作或关卡逻辑。[br]
## 将相机加入 main_camera Group，或在场景就绪后调用 set_camera()。没有震动时不进入帧循环。

## trauma 完全衰减且相机恢复基准变换后发出。
signal shake_finished

var _camera: Camera2D
var _base_offset := Vector2.ZERO
var _base_rotation_degrees := 0.0
var _trauma := 0.0
var _trauma_power := 2.0
var _decay_rate := 2.2
var _max_offset := Vector2(12.0, 9.0)
var _max_rotation_degrees := 1.5
var _noise: FastNoiseLite
var _noise_time := 0.0

func _ready() -> void:
	set_process(false)

## 显式绑定当前场景的主相机，并记录它的稳定 offset 与 rotation。
func set_camera(camera: Camera2D) -> void:
	if is_instance_valid(_camera) and _camera != camera:
		_reset_camera_transform()
	_camera = camera
	if is_instance_valid(_camera):
		_base_offset = _camera.offset
		_base_rotation_degrees = _camera.rotation_degrees

## 返回当前有效相机；没有时尝试查找 main_camera Group。
func get_camera() -> Camera2D:
	_ensure_camera()
	return _camera

## 配置持续震动。通常在游戏启动时调用一次。
func configure_shake(
	max_offset := Vector2(12.0, 9.0),
	max_rotation_degrees := 1.5,
	decay_rate := 2.2,
	trauma_power := 2.0
) -> void:
	_max_offset = max_offset.abs()
	_max_rotation_degrees = absf(max_rotation_degrees)
	_decay_rate = maxf(decay_rate, 0.01)
	_trauma_power = maxf(trauma_power, 1.0)

## 增加 0 到 1 的震动强度。多次冲击会累加，但不会超过 1。
func add_trauma(amount := 0.25) -> void:
	if amount <= 0.0:
		return
	_ensure_camera()
	if not is_instance_valid(_camera):
		return
	_ensure_noise()
	_trauma = clampf(_trauma + amount, 0.0, 1.0)
	set_process(true)

## 立即停止震动并恢复相机基准变换。
func clear_trauma() -> void:
	var was_shaking := _trauma > 0.0
	_trauma = 0.0
	set_process(false)
	_reset_camera_transform()
	if was_shaking:
		shake_finished.emit()

## 当前是否仍在震动。
func is_shaking() -> bool:
	return _trauma > 0.0 and is_instance_valid(_camera)

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

func _ensure_noise() -> void:
	if _noise:
		return
	_noise = FastNoiseLite.new()
	_noise.seed = randi()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.08

func _reset_camera_transform() -> void:
	if not is_instance_valid(_camera):
		return
	_camera.offset = _base_offset
	_camera.rotation_degrees = _base_rotation_degrees
