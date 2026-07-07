extends Node
class_name AudioService

# AudioService.gd
# 统一音效管理服务，避免节点直接播放 AudioStreamPlayer
# 挂载方式：设为 Autoload，名称 "AudioService"
#
# 设计原则：
# - 所有音效通过这个 Service 播放，不直接在节点里 new AudioStreamPlayer
# - 自动限制同时播放的同音效数量，防止声音重叠炸耳
# - 支持音量/静音的全局控制

# ========== 音量设置 ==========
var master_volume: float = 1.0:
	set(v):
		master_volume = clampf(v, 0.0, 1.0)
		_apply_volume()

var sfx_volume: float = 1.0:
	set(v):
		sfx_volume = clampf(v, 0.0, 1.0)
		_apply_volume()

var bgm_volume: float = 1.0:
	set(v):
		bgm_volume = clampf(v, 0.0, 1.0)
		_apply_volume()

var muted: bool = false:
	set(v):
		muted = v
		_apply_volume()


# ========== 内部状态 ==========
var _bgm_player: AudioStreamPlayer = null
var _sfx_pool: Array[AudioStreamPlayer] = []
var _max_sfx_pool: int = 8
var _bus_name: String = "Master"


# ========== 生命周期 ==========
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 暂停时仍能播放 UI 音效


# ========== BGM ==========

## 播放 BGM，自动替换当前正在播放的
func play_bgm(stream: AudioStream, fade_time: float = 0.5) -> void:
	if _bgm_player == null:
		_bgm_player = AudioStreamPlayer.new()
		_bgm_player.bus = _bus_name
		add_child(_bgm_player)

	# 简单的淡入淡出（可选，先直接切）
	_bgm_player.stream = stream
	_bgm_player.volume_db = _linear_to_db(bgm_volume * master_volume * (0.0 if muted else 1.0))
	_bgm_player.play()


## 停止 BGM
func stop_bgm() -> void:
	if _bgm_player and _bgm_player.playing:
		_bgm_player.stop()


# ========== SFX ==========

## 播放音效，自动从对象池取可用 player
func play_sfx(stream: AudioStream, volume_scale: float = 1.0) -> void:
	if stream == null:
		return

	var player := _get_available_sfx_player()
	player.stream = stream
	player.volume_db = _linear_to_db(sfx_volume * master_volume * volume_scale * (0.0 if muted else 1.0))
	player.play()


## 停止所有音效
func stop_all_sfx() -> void:
	for p in _sfx_pool:
		p.stop()


# ========== 内部方法 ==========

func _get_available_sfx_player() -> AudioStreamPlayer:
	# 先找空闲的
	for p in _sfx_pool:
		if not p.playing:
			return p

	# 池满了就复用最老的
	if _sfx_pool.size() >= _max_sfx_pool:
		var oldest = _sfx_pool.pop_front()
		oldest.stop()
		_sfx_pool.append(oldest)
		return oldest

	# 新建
	var new_player := AudioStreamPlayer.new()
	new_player.bus = _bus_name
	add_child(new_player)
	_sfx_pool.append(new_player)
	return new_player


func _apply_volume() -> void:
	var master_db := _linear_to_db(master_volume * (0.0 if muted else 1.0))
	var sfx_db := _linear_to_db(sfx_volume * master_volume * (0.0 if muted else 1.0))
	var bgm_db := _linear_to_db(bgm_volume * master_volume * (0.0 if muted else 1.0))

	# 如果有 AudioServer 可用，设置总线音量
	if _bgm_player:
		_bgm_player.volume_db = bgm_db

	for p in _sfx_pool:
		p.volume_db = sfx_db


static func _linear_to_db(lin: float) -> float:
	if lin <= 0.0:
		return -80.0
	return 20.0 * log(lin) / log(10.0)
