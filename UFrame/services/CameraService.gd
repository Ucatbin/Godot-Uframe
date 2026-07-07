extends Node
class_name CameraService

# CameraService.gd
# 相机特效服务：屏幕震动、慢动作、跟随目标
# 挂载方式：设为 Autoload，名称 "CameraService"
#
# 使用前提：当前场景有 Camera2D 节点，
# 可以通过 Group "main_camera" 或手动 set_camera() 指定

signal trauma_decayed   # 震动完全停止时发出

var _camera: Camera2D = null
var _trauma: float = 0.0          # 当前震动强度 0.0 ~ 1.0
var _trauma_power: float = 2.0     # 震动衰减曲线指数
var _decay_rate: float = 1.5       # 每秒 trauma 衰减速度
var _max_offset: float = 30.0      # 最大像素偏移
var _max_roll: float = 10.0        # 最大旋转角度（度）
var _noise: FastNoiseLite = null
var _noise_seed: int = 0


# ========== 公共方法 ==========

## 手动设置相机（如果不想用 Group 查找）
func set_camera(cam: Camera2D) -> void:
	_camera = cam


## 添加震动强度（推荐 0.3 ~ 1.0）
func add_trauma(amount: float = 0.5) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)
	if _camera == null:
		_try_find_camera()


## 立即停止震动
func clear_trauma() -> void:
	_trauma = 0.0
	_reset_camera_transform()


## 设置慢动作（time_scale < 1.0）
func set_time_scale(scale: float = 1.0, duration: float = 0.0) -> void:
	Engine.time_scale = clampf(scale, 0.1, 2.0)
	if duration > 0.0:
		# 定时恢复
		_reset_time_scale_after(duration)


# ========== 生命周期 ==========
func _ready() -> void:
	_try_find_camera()
	_noise = FastNoiseLite.new()
	_noise_seed = randi()
	_noise.seed = _noise_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH


func _process(delta: float) -> void:
	if _trauma > 0.0:
		# 衰减
		_trauma = clampf(_trauma - _decay_rate * delta, 0.0, 1.0)
		if _trauma == 0.0:
			_reset_camera_transform()
			trauma_decayed.emit()
			return

		# 根据 trauma 计算偏移
		var shake := pow(_trauma, _trauma_power)
		var time := Time.get_time_dict_from_system()
		var t := (time.hour * 3600 + time.minute * 60 + time.second) as float

		var ox := _max_offset * shake * _noise.get_noise_1d(t * 10.0)
		var oy := _max_offset * shake * _noise.get_noise_1d(t * 10.0 + 100.0)
		var rot := _max_roll * shake * _noise.get_noise_1d(t * 10.0 + 200.0)

		if _camera:
			_camera.offset = Vector2(ox, oy)
			_camera.rotation_degrees = rot


# ========== 内部方法 ==========

func _try_find_camera() -> void:
	var cameras := get_tree().get_nodes_in_group("main_camera")
	if cameras.size() > 0:
		_camera = cameras[0] as Camera2D
		if _camera == null:
			push_warning("[CameraService] Group 'main_camera' 中的节点不是 Camera2D")


func _reset_camera_transform() -> void:
	if _camera:
		_camera.offset = Vector2.ZERO
		_camera.rotation_degrees = 0.0


func _reset_time_scale_after(duration: float) -> void:
	# 简单延迟恢复（不依赖 SceneTreeTimer 的复杂回调）
	await get_tree().create_timer(duration, true, true, true).timeout
	Engine.time_scale = 1.0
