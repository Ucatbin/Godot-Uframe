extends Node
class_name CameraService

# CameraService.gd
# 相机特效服务：屏幕震动、慢动作、跟随目标 —— 对标 DOTween Camera shortcuts
# 挂载方式：设为 Autoload，名称 "CameraService"
#
# 使用前提：当前场景有 Camera2D 节点，
# 可以通过 Group "main_camera" 或手动 set_camera() 指定
#
# 使用示例：
#   # 简单震动（基于 trauma 持续震动）
#   CameraService.add_trauma(0.5)
#
#   # 一次性震动（对标 DOTween Camera.DOShakePosition）
#   CameraService.shake_position(0.3, Vector2(10, 10), 10, 90.0, true)
#
#   # 一次性旋转震动（对标 DOTween Camera.DOShakeRotation）
#   CameraService.shake_rotation(0.3, 5.0, 10, 90.0, true)
#
#   # 冲击效果（对标 DOTween Camera.DOPunchPosition）
#   CameraService.punch(Vector2(20, 0), 0.5, 6, 1.0)

# =============================================================================
# 信号
# =============================================================================
signal trauma_decayed         # 震动完全停止时发出
signal shake_finished         # 一次性震动完成时发出

# =============================================================================
# ShakeRandomnessMode 枚举 —— 对标 DOTween
# =============================================================================
enum ShakeRandomnessMode {
	FULL,           # 完全随机（默认）
	HARMONIC,       # 谐波随机（更平滑的噪声）
}

# =============================================================================
# 内部变量
# =============================================================================
var _camera: Camera2D = null
var _trauma: float = 0.0               # 当前震动强度 0.0 ~ 1.0
var _trauma_power: float = 2.0          # 震动衰减曲线指数
var _decay_rate: float = 1.5            # 每秒 trauma 衰减速度
var _max_offset: float = 30.0           # 最大像素偏移
var _max_roll: float = 10.0             # 最大旋转角度（度）
var _noise: FastNoiseLite = null
var _noise_seed: int = 0
var _noise_time: float = 0.0            # 递增的时间偏移，防止震动"卡住"

# 一次性震动状态
var _shake_tween: Tween = null
var _shake_active: bool = false


# =============================================================================
# 公共方法 ———— 相机管理
# =============================================================================

## 手动设置相机（如果不想用 Group 查找）
func set_camera(cam: Camera2D) -> void:
	_camera = cam


## 尝试自动查找相机（通过 Group "main_camera"）
func try_find_camera() -> Camera2D:
	_try_find_camera()
	return _camera


# =============================================================================
# 公共方法 ———— 持续震动（Trauma 模式）
# =============================================================================

## 添加震动强度（推荐 0.3 ~ 1.0）
func add_trauma(amount: float = 0.5) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)
	if _camera == null:
		_try_find_camera()


## 设置震动参数 —— 对标 DOTween 的 SetXxx 链式风格
func set_shake_params(max_offset: float = 30.0, max_roll: float = 10.0, decay_rate: float = 1.5, trauma_power: float = 2.0) -> void:
	_max_offset = max_offset
	_max_roll = max_roll
	_decay_rate = decay_rate
	_trauma_power = trauma_power


## 立即停止持续震动
func clear_trauma() -> void:
	_trauma = 0.0
	_reset_camera_transform()


# =============================================================================
# 公共方法 ———— 一次性震动（对标 DOTween DOShakePosition / DOShakeRotation）
# =============================================================================

## 震动位置 —— 对标 Camera.DOShakePosition()
## [param duration]: 震动持续时间
## [param strength]: 震动强度（像素），Vector2 可分别设置 X/Y，也可传 float
## [param vibrato]: 振动频率（来回震荡次数），默认 10
## [param randomness]: 随机性程度 [0, 180]，默认 90（越大越随机）
## [param fade_out]: 是否逐渐衰减（默认 true）
## [param mode]: 随机模式（FULL 或 HARMONIC）
func shake_position(duration: float, strength: Variant = Vector2(10, 10), vibrato: int = 10, randomness: float = 90.0, fade_out: bool = true, mode: ShakeRandomnessMode = ShakeRandomnessMode.FULL) -> void:
	if _camera == null:
		_try_find_camera()
	if _camera == null:
		return

	# 解析 strength 参数
	var str_vec: Vector2
	if strength is Vector2:
		str_vec = strength
	elif strength is float or strength is int:
		str_vec = Vector2(float(strength), float(strength))
	else:
		str_vec = Vector2(10, 10)

	_stop_shake_tween()
	_shake_tween = create_tween()
	
	var original_offset := _camera.offset
	var total_steps := vibrato * 2 + 1  # +1 用于回到原位
	var step_duration := duration / float(total_steps)
	
	if mode == ShakeRandomnessMode.FULL:
		# 完全随机模式：每步生成随机偏移
		for i in range(total_steps - 1):
			var progress := float(i) / float(total_steps)
			var intensity := 1.0 - progress if fade_out else 1.0
			var rx := (randf() * 2.0 - 1.0) * str_vec.x * intensity * (randomness / 90.0)
			var ry := (randf() * 2.0 - 1.0) * str_vec.y * intensity * (randomness / 90.0)
			_shake_tween.tween_property(_camera, "offset", Vector2(rx, ry), step_duration)
	else:
		# 谐波模式：复用 _noise 实例，只更新 seed
		if _noise == null:
			_noise = FastNoiseLite.new()
			_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.seed = randi()
		_noise.frequency = vibrato * 0.1
		for i in range(total_steps - 1):
			var progress := float(i) / float(total_steps)
			var intensity := 1.0 - progress if fade_out else 1.0
			var time_off := float(i) * 0.5
			var ox := str_vec.x * intensity * _noise.get_noise_1d(time_off) * (randomness / 90.0)
			var oy := str_vec.y * intensity * _noise.get_noise_1d(time_off + 100.0) * (randomness / 90.0)
			_shake_tween.tween_property(_camera, "offset", Vector2(ox, oy), step_duration)
	
	# 回到原位
	_shake_tween.tween_property(_camera, "offset", original_offset, step_duration * 0.5)
	_shake_tween.tween_callback(func():
		_shake_active = false
		shake_finished.emit()
	)
	_shake_active = true


## 震动旋转 —— 对标 Camera.DOShakeRotation()
## [param duration]: 震动持续时间
## [param strength]: 最大旋转角度（度）
## [param vibrato]: 振动频率（来回震荡次数），默认 10
## [param randomness]: 随机性程度 [0, 180]，默认 90
## [param fade_out]: 是否逐渐衰减（默认 true）
func shake_rotation(duration: float, strength: float = 5.0, vibrato: int = 10, randomness: float = 90.0, fade_out: bool = true) -> void:
	if _camera == null:
		_try_find_camera()
	if _camera == null:
		return

	_stop_shake_tween()
	_shake_tween = create_tween()
	
	var original_rotation := _camera.rotation_degrees
	var total_steps := vibrato * 2 + 1
	var step_duration := duration / float(total_steps)
	
	for i in range(total_steps - 1):
		var progress := float(i) / float(total_steps)
		var intensity := 1.0 - progress if fade_out else 1.0
		var rv := (randf() * 2.0 - 1.0) * strength * intensity * (randomness / 90.0)
		_shake_tween.tween_property(_camera, "rotation_degrees", rv, step_duration)
	
	_shake_tween.tween_property(_camera, "rotation_degrees", original_rotation, step_duration * 0.5)
	_shake_tween.tween_callback(func():
		_shake_active = false
		shake_finished.emit()
	)
	_shake_active = true


## 同时震动位置和旋转
func shake_both(duration: float, position_strength: Vector2 = Vector2(10, 10), rotation_strength: float = 5.0, vibrato: int = 10, randomness: float = 90.0, fade_out: bool = true) -> void:
	if _camera == null:
		_try_find_camera()
	if _camera == null:
		return

	_stop_shake_tween()
	_shake_tween = create_tween()
	
	var original_offset := _camera.offset
	var original_rotation := _camera.rotation_degrees
	var total_steps := vibrato * 2 + 1
	var step_duration := duration / float(total_steps)
	
	for i in range(total_steps - 1):
		var progress := float(i) / float(total_steps)
		var intensity := 1.0 - progress if fade_out else 1.0
		var rx := (randf() * 2.0 - 1.0) * position_strength.x * intensity * (randomness / 90.0)
		var ry := (randf() * 2.0 - 1.0) * position_strength.y * intensity * (randomness / 90.0)
		var rv := (randf() * 2.0 - 1.0) * rotation_strength * intensity * (randomness / 90.0)
		_shake_tween.parallel().tween_property(_camera, "offset", Vector2(rx, ry), step_duration)
		_shake_tween.parallel().tween_property(_camera, "rotation_degrees", rv, step_duration)
	
	_shake_tween.parallel().tween_property(_camera, "offset", original_offset, step_duration * 0.5)
	_shake_tween.parallel().tween_property(_camera, "rotation_degrees", original_rotation, step_duration * 0.5)
	_shake_tween.tween_callback(func():
		_shake_active = false
		shake_finished.emit()
	)
	_shake_active = true


# =============================================================================
# 公共方法 ———— Punch 冲击效果（对标 DOTween.DOPunchPosition）
# =============================================================================

## Punch 冲击：先向指定方向冲过去，然后震荡回原位
## [param punch]: 冲击方向和强度（像素）
## [param duration]: 持续时间
## [param vibrato]: 震荡次数
## [param elasticity]: 弹性衰减系数 (0~1，越小衰减越快)，默认 1.0
func punch(punch: Vector2, duration: float = 0.5, vibrato: int = 6, elasticity: float = 1.0) -> void:
	if _camera == null:
		_try_find_camera()
	if _camera == null:
		return

	_stop_shake_tween()
	_shake_tween = create_tween()
	
	var original_offset := _camera.offset
	var total_steps := vibrato * 2 + 2  # +1 for punch, +1 for return
	var step_duration := duration / float(total_steps)
	
	# 第一步：冲向 punch
	_shake_tween.tween_property(_camera, "offset", original_offset + punch, step_duration)
	
	# 震荡衰减回原位
	for i in range(vibrato):
		var decay := pow(elasticity, float(i + 1))
		var offset := punch * decay
		if i % 2 == 0:
			offset = -offset
		_shake_tween.tween_property(_camera, "offset", original_offset + offset, step_duration)
	
	# 最后回到原位
	_shake_tween.tween_property(_camera, "offset", original_offset, step_duration * 0.5)
	_shake_tween.tween_callback(func():
		_shake_active = false
		shake_finished.emit()
	)
	_shake_active = true


# =============================================================================
# 公共方法 ———— 慢动作 / 时间缩放（对标 DOTween.DOTimeScale）
# =============================================================================

## 设置时间缩放（慢动作 time_scale < 1.0，快放 > 1.0）
## [param scale]: 时间缩放倍数，范围 [0.1, 2.0]
## [param duration]: 持续时间（> 0 时自动恢复），默认 0 表示永久
## [param ease_type]: 恢复时的缓动类型（需 Easing 脚本存在）
func set_time_scale(scale: float = 1.0, duration: float = 0.0) -> void:
	Engine.time_scale = clampf(scale, 0.1, 2.0)
	if duration > 0.0:
		_reset_time_scale_after(duration)


## 立即恢复正常时间
func reset_time_scale() -> void:
	Engine.time_scale = 1.0


# =============================================================================
# 公共方法 ———— 平滑跟随（对标 DOTween 的路径跟随思路）
# =============================================================================

## 平滑跟随目标
## [param target]: 要跟随的节点
## [param smooth_speed]: 跟随速度（越大越快），默认 5.0
func follow_target(target: Node2D, smooth_speed: float = 5.0) -> void:
	if _camera == null:
		_try_find_camera()
	if _camera == null or target == null:
		return
	_camera.position = _camera.position.lerp(target.position, smooth_speed * get_process_delta_time())


## 平滑移动到指定位置（对标 DOTween Camera.DOMove，但持续跟随）
func move_to(target_pos: Vector2, smooth_speed: float = 5.0) -> void:
	if _camera == null:
		_try_find_camera()
	if _camera == null:
		return
	_camera.position = _camera.position.lerp(target_pos, smooth_speed * get_process_delta_time())


# =============================================================================
# 公共方法 ———— FOV / Zoom 动画（对标 DOTween Camera.DOOrthoSize）
# =============================================================================

## 缩放（2D 相机 zoom）
func zoom_to(zoom: Vector2, duration: float = 0.5) -> void:
	if _camera == null:
		_try_find_camera()
	if _camera == null:
		return
	var tween := create_tween()
	tween.tween_property(_camera, "zoom", zoom, duration)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


# =============================================================================
# 生命周期
# =============================================================================

func _ready() -> void:
	_try_find_camera()
	_noise = FastNoiseLite.new()
	_noise_seed = randi()
	_noise.seed = _noise_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.05


func _process(delta: float) -> void:
	if _trauma > 0.0:
		# 衰减
		_trauma = clampf(_trauma - _decay_rate * delta, 0.0, 1.0)
		if _trauma == 0.0:
			_reset_camera_transform()
			trauma_decayed.emit()
			return

		_noise_time += delta * 10.0
		
		# 根据 trauma 计算偏移（使用 Easing 风格的非线性映射）
		var shake := pow(_trauma, _trauma_power)

		var ox := _max_offset * shake * _noise.get_noise_1d(_noise_time)
		var oy := _max_offset * shake * _noise.get_noise_1d(_noise_time + 100.0)
		var rot := _max_roll * shake * _noise.get_noise_1d(_noise_time + 200.0)

		if _camera and not _shake_active:
			_camera.offset = Vector2(ox, oy)
			_camera.rotation_degrees = rot


# =============================================================================
# 内部方法
# =============================================================================

func _try_find_camera() -> void:
	var cameras := get_tree().get_nodes_in_group("main_camera")
	if cameras.size() > 0:
		_camera = cameras[0] as Camera2D
		if _camera == null:
			push_warning("[CameraService] Group 'main_camera' 中的节点不是 Camera2D")


func _reset_camera_transform() -> void:
	if _camera and not _shake_active:
		_camera.offset = Vector2.ZERO
		_camera.rotation_degrees = 0.0


func _stop_shake_tween() -> void:
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = null
	_shake_active = false


func _reset_time_scale_after(duration: float) -> void:
	await get_tree().create_timer(duration, true, true, true).timeout
	Engine.time_scale = 1.0
