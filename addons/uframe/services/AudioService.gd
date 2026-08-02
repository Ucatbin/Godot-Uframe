class_name UFrameAudio
extends Node

## 可选的非空间音频服务，通过 UFrame.audio 使用。
##
## 服务复用少量 AudioStreamPlayer，适合 BGM、UI 与普通全局音效。[br]
## 需要距离衰减时，请直接在场景中使用 AudioStreamPlayer2D/3D。

## 所有声音的总音量，范围 0 到 1。
var master_volume := 1.0:
	set(value):
		master_volume = clampf(value, 0.0, 1.0)
		_apply_volume()
## 音效音量，范围 0 到 1。
var sfx_volume := 1.0:
	set(value):
		sfx_volume = clampf(value, 0.0, 1.0)
		_apply_volume()
## 背景音乐音量，范围 0 到 1。
var bgm_volume := 1.0:
	set(value):
		bgm_volume = clampf(value, 0.0, 1.0)
		_apply_volume()
## 静音不会停止播放进度，取消后可继续听到声音。
var muted := false:
	set(value):
		muted = value
		_apply_volume()

var _bgm_player: AudioStreamPlayer
var _bgm_tween: Tween
var _bgm_generation := 0
var _sfx_pool: Array[AudioStreamPlayer] = []
var _max_sfx_players := 8
var _bus_name: StringName = &"Master"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _exit_tree() -> void:
	_kill_bgm_tween()
	if _bgm_player:
		_bgm_player.stop()
		_bgm_player.stream = null
	for player in _sfx_pool:
		player.stop()
		player.stream = null

## 配置音频总线和最大同时音效数。建议在游戏启动时调用一次。
func configure(bus_name: StringName = &"Master", max_sfx_players := 8) -> void:
	_bus_name = bus_name
	_max_sfx_players = maxi(max_sfx_players, 1)
	if _bgm_player:
		_bgm_player.bus = _bus_name
	for player in _sfx_pool:
		player.bus = _bus_name

## 播放背景音乐。已有音乐时先淡出，再切换并淡入；连续调用只保留最后一次请求。
func play_bgm(stream: AudioStream, fade_time := 0.5) -> void:
	if stream == null:
		stop_bgm(fade_time)
		return
	_ensure_bgm_player()
	_bgm_generation += 1
	var generation := _bgm_generation
	_kill_bgm_tween()
	if _bgm_player.playing and fade_time > 0.0:
		_start_bgm_fade(-80.0, fade_time * 0.5, generation, func() -> void:
			_start_stream(stream, fade_time * 0.5, generation)
		)
	else:
		_start_stream(stream, maxf(fade_time, 0.0), generation)

## 停止背景音乐。fade_time 大于 0 时先淡出。
func stop_bgm(fade_time := 0.0) -> void:
	if not _bgm_player:
		return
	if not _bgm_player.playing:
		# stop 后清掉流引用，让生成式/解码式 Playback 能尽快释放。
		_bgm_player.stream = null
		return
	_bgm_generation += 1
	var generation := _bgm_generation
	_kill_bgm_tween()
	if fade_time > 0.0:
		_start_bgm_fade(-80.0, fade_time, generation, func() -> void:
			if _bgm_player:
				_bgm_player.stop()
				_bgm_player.stream = null
		)
	else:
		_bgm_player.stop()
		_bgm_player.stream = null

## 播放非空间音效并返回所用播放器。全部占用时复用最早的播放器。
func play_sfx(stream: AudioStream, volume_scale := 1.0, pitch_scale := 1.0) -> AudioStreamPlayer:
	if stream == null:
		return null
	var player := _get_available_sfx_player()
	player.stream = stream
	player.set_meta(&"uframe_volume_scale", clampf(volume_scale, 0.0, 1.0))
	player.volume_db = _get_sfx_db(player)
	player.pitch_scale = maxf(pitch_scale, 0.01)
	player.play()
	return player

## 立即停止当前播放的全部音效，不影响 BGM。
func stop_all_sfx() -> void:
	for player in _sfx_pool:
		player.stop()

func _start_stream(stream: AudioStream, fade_time: float, generation: int) -> void:
	if generation != _bgm_generation or not _bgm_player:
		return
	_bgm_player.stream = stream
	_bgm_player.volume_db = -80.0 if fade_time > 0.0 else _get_bgm_db()
	_bgm_player.play()
	if fade_time > 0.0:
		_start_bgm_fade(_get_bgm_db(), fade_time, generation)

func _start_bgm_fade(target_db: float, duration: float, generation: int, completed := Callable()) -> void:
	var tween := create_tween()
	_bgm_tween = tween
	tween.tween_property(_bgm_player, "volume_db", target_db, duration)
	tween.finished.connect(func() -> void:
		if generation != _bgm_generation or _bgm_tween != tween:
			return
		_bgm_tween = null
		if completed.is_valid():
			completed.call()
	, CONNECT_ONE_SHOT)

func _ensure_bgm_player() -> void:
	if _bgm_player:
		return
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = _bus_name
	add_child(_bgm_player)

func _get_available_sfx_player() -> AudioStreamPlayer:
	for player in _sfx_pool:
		if not player.playing:
			return player
	if _sfx_pool.size() >= _max_sfx_players:
		var oldest := _sfx_pool.pop_front()
		oldest.stop()
		_sfx_pool.append(oldest)
		return oldest
	var player := AudioStreamPlayer.new()
	player.bus = _bus_name
	add_child(player)
	_sfx_pool.append(player)
	return player

func _apply_volume() -> void:
	# 音量或静音变化应立即生效；取消旧淡变可避免它稍后覆盖新设置。
	if _bgm_tween:
		_bgm_generation += 1
		_kill_bgm_tween()
	if _bgm_player:
		_bgm_player.volume_db = _get_bgm_db()
	for player in _sfx_pool:
		player.volume_db = _get_sfx_db(player)

func _get_bgm_db() -> float:
	return _linear_volume_to_db(bgm_volume * master_volume if not muted else 0.0)

func _get_sfx_db(player: AudioStreamPlayer) -> float:
	var per_sound := float(player.get_meta(&"uframe_volume_scale", 1.0))
	return _linear_volume_to_db(sfx_volume * master_volume * per_sound if not muted else 0.0)

func _linear_volume_to_db(value: float) -> float:
	return linear_to_db(value) if value > 0.0001 else -80.0

func _kill_bgm_tween() -> void:
	if _bgm_tween and _bgm_tween.is_valid():
		_bgm_tween.kill()
	_bgm_tween = null
