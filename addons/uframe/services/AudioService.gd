extends Node

## 可选非空间音频服务
##
## 通过 [code]UFrame.audio[/code] 使用，复用少量 [AudioStreamPlayer] 播放 BGM、UI 与普通全局音效[br]
## 需要距离衰减时，应直接在场景中使用 [AudioStreamPlayer2D] 或 [AudioStreamPlayer3D]
class_name UFrameAudio

#region 配置
## [b]总音量[/b][br]
## 范围为 [code]0.0[/code] 到 [code]1.0[/code]
var master_volume := 1.0:
	set(value):
		master_volume = clampf(value, 0.0, 1.0)
		_apply_volume()

## [b]音效音量[/b][br]
## 范围为 [code]0.0[/code] 到 [code]1.0[/code]
var sfx_volume := 1.0:
	set(value):
		sfx_volume = clampf(value, 0.0, 1.0)
		_apply_volume()

## [b]背景音乐音量[/b][br]
## 范围为 [code]0.0[/code] 到 [code]1.0[/code]
var bgm_volume := 1.0:
	set(value):
		bgm_volume = clampf(value, 0.0, 1.0)
		_apply_volume()

## [b]是否静音[/b][br]
## 不会停止播放进度，取消后可继续听到声音
var muted := false:
	set(value):
		muted = value
		_apply_volume()
#endregion

#region 运行时状态
## [b]背景音乐播放器[/b]
var _bgm_player: AudioStreamPlayer

## [b]背景音乐淡变[/b]
var _bgm_tween: Tween

## [b]背景音乐请求代次[/b][br]
## 用于取消连续调用产生的旧异步回调
var _bgm_generation := 0

## [b]音效播放器池[/b]
var _sfx_pool: Array[AudioStreamPlayer] = []

## [b]最大音效播放器数[/b]
var _max_sfx_players := 8

## [b]音频总线名[/b]
var _bus_name: StringName = &"Master"
#endregion

#region 生命周期
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
#endregion

#region 主要方法
## [b]配置音频服务[/b][br]
## 设置音频总线与最大同时音效数，建议在游戏启动时调用一次[br][br]
## [param bus_name] : 音频总线名[br]
## [param max_sfx_players] : 最大音效播放器数
func configure(bus_name: StringName = &"Master", max_sfx_players := 8) -> void:
	_bus_name = bus_name
	_max_sfx_players = maxi(max_sfx_players, 1)
	if _bgm_player:
		_bgm_player.bus = _bus_name
	for player in _sfx_pool:
		player.bus = _bus_name

## [b]播放背景音乐[/b][br]
## 已有音乐时先淡出再切换并淡入；连续调用只保留最后一次请求[br][br]
## [param stream] : 需要播放的音频流，空值表示停止[br]
## [param fade_time] : 完整切换使用的淡变秒数
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

## [b]停止背景音乐[/b][br]
## [param fade_time] 大于 [code]0.0[/code] 时先淡出[br][br]
## [param fade_time] : 淡出秒数
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

## [b]播放非空间音效[/b][br]
## 返回所用播放器；播放器全部占用时复用最早的一项[br][br]
## [param stream] : 需要播放的音频流[br]
## [param volume_scale] : 本次音效音量倍率[br]
## [param pitch_scale] : 本次音效音高倍率
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

## [b]停止全部音效[/b][br]
## 不影响背景音乐
func stop_all_sfx() -> void:
	for player in _sfx_pool:
		player.stop()
#endregion

#region 内部方法
## [b]开始播放背景音乐流[/b][br]
## 请求代次已经失效时取消操作[br][br]
## [param stream] : 需要播放的音频流[br]
## [param fade_time] : 淡入秒数[br]
## [param generation] : 发起请求时的代次
func _start_stream(stream: AudioStream, fade_time: float, generation: int) -> void:
	if generation != _bgm_generation or not _bgm_player:
		return
	_bgm_player.stream = stream
	_bgm_player.volume_db = -80.0 if fade_time > 0.0 else _get_bgm_db()
	_bgm_player.play()
	if fade_time > 0.0:
		_start_bgm_fade(_get_bgm_db(), fade_time, generation)

## [b]开始背景音乐淡变[/b][br]
## 仅最新请求会执行完成回调[br][br]
## [param target_db] : 目标分贝值[br]
## [param duration] : 淡变秒数[br]
## [param generation] : 发起请求时的代次[br]
## [param completed] : 可选的完成回调
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

## [b]确保背景音乐播放器可用[/b]
func _ensure_bgm_player() -> void:
	if _bgm_player:
		return
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = _bus_name
	add_child(_bgm_player)

## [b]获取可用音效播放器[/b][br]
## 没有空闲项且达到上限时轮换最早的播放器
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

## [b]应用音量配置[/b][br]
## 取消旧淡变，立即同步当前背景音乐和全部音效播放器
func _apply_volume() -> void:
	# 音量或静音变化应立即生效；取消旧淡变可避免它稍后覆盖新设置。
	if _bgm_tween:
		_bgm_generation += 1
		_kill_bgm_tween()
	if _bgm_player:
		_bgm_player.volume_db = _get_bgm_db()
	for player in _sfx_pool:
		player.volume_db = _get_sfx_db(player)

## [b]获取背景音乐分贝值[/b]
func _get_bgm_db() -> float:
	return _linear_volume_to_db(bgm_volume * master_volume if not muted else 0.0)

## [b]获取音效分贝值[/b][br][br]
## [param player] : 需要计算音量的音效播放器
func _get_sfx_db(player: AudioStreamPlayer) -> float:
	var per_sound := float(player.get_meta(&"uframe_volume_scale", 1.0))
	return _linear_volume_to_db(sfx_volume * master_volume * per_sound if not muted else 0.0)

## [b]转换线性音量为分贝[/b][br]
## 接近静音时返回 [code]-80.0[/code][br][br]
## [param value] : 线性音量值
func _linear_volume_to_db(value: float) -> float:
	return linear_to_db(value) if value > 0.0001 else -80.0

## [b]取消背景音乐淡变[/b]
func _kill_bgm_tween() -> void:
	if _bgm_tween and _bgm_tween.is_valid():
		_bgm_tween.kill()
	_bgm_tween = null
#endregion
