extends Node
class_name TweenService

# TweenService.gd
# 对标 DOTween 的补间动画引擎 —— Autoload 单例，名称 "TweenService"
#
# 核心理念（与 DOTween 一致）：
#   - Tweener: 控制一个值/属性并动画化
#   - Sequence: 控制一组 Tweener/Sequence 并顺序/并行播放
#   - 链式 API：DoXxx().SetEase().SetDelay().OnComplete()
#
# 用法示例：
#   # 属性补间
#   TweenService.DoProperty(node, "position", Vector2(100, 0), 1.0)\
#     .SetEase(Easing.Type.OUT_BACK).SetDelay(0.5).OnComplete(func(): print("done"))
#
#   # 泛型补间（getter/setter）
#   TweenService.DoFloat(0.0, 100.0, 1.0, func(v): health_bar.value = v)\
#     .SetEase(Easing.Type.OUT_QUAD)
#
#   # Sequence
#   var seq = TweenService.Sequence()
#   seq.Append(TweenService.DoMove(sprite, Vector2(100, 0), 0.5))
#   seq.Join(TweenService.DoFade(sprite, 0.5, 0.5))
#   seq.AppendInterval(0.3)
#   seq.OnComplete(func(): queue_free())

# =============================================================================
# 信号
# =============================================================================
signal tween_created(tween_id: int)
signal tween_killed(tween_id: int)
signal tween_completed(tween_id: int)

# =============================================================================
# LoopType 枚举
# =============================================================================
enum LoopType {
	RESTART,     # 每次循环从头开始（默认）
	YOYO,        # 来回往返
	INCREMENTAL, # 每次循环从当前终点继续累加
}

# =============================================================================
# UpdateType 枚举
# =============================================================================
enum UpdateType {
	NORMAL,              # _process（受 time_scale 影响）
	FIXED,               # _physics_process
	UNSCALED,            # _process + 忽略 time_scale
}

# =============================================================================
# 内部数据结构
# =============================================================================
class TweenEntry:
	var id: int
	var godot_tween: Tween = null
	var target: Object = null
	var is_sequence: bool = false
	var _ease_type: Easing.Type = Easing.Type.OUT_QUAD
	var _loops: int = 1
	var _loop_type: LoopType = LoopType.RESTART
	var _delay: float = 0.0
	var _auto_kill: bool = true
	var _is_relative: bool = false
	var _time_scale: float = 1.0
	var _update_type: UpdateType = UpdateType.NORMAL
	var _on_start: Callable
	var _on_update: Callable
	var _on_complete: Callable
	var _on_kill: Callable
	var _on_pause: Callable
	var _on_play: Callable
	var _on_step_complete: Callable
	var _is_paused: bool = false
	var _is_playing: bool = false
	var _is_complete: bool = false
	var _is_killed: bool = false
	var _tween_id_for_kill: StringName = &""


# =============================================================================
# 内部状态
# =============================================================================
var _next_id: int = 0
var _tweens: Dictionary = {}        # id → TweenEntry
var _node: Node                      # 用于挂载 Godot Tween 的宿主节点


# =============================================================================
# 生命周期
# =============================================================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_node = self


# =============================================================================
# ---- 泛型补间（对标 DOTween.To）----
# =============================================================================

## 泛型 float 补间 —— 对标 DOTween.To(getter, setter, to, duration)
## [br]例：TweenService.DoFloat(0, 100, 1, func(v): bar.value = v)
func DoFloat(from: float, to: float, duration: float, on_update: Callable) -> TweenEntry:
	var entry := _create_entry()
	var tween := _create_godot_tween(entry)
	_set_delay(entry, tween)

	# 用 tween_method 实现连续回调，并应用自定义缓动
	tween.tween_method(
		func(t: float):
			if not entry._is_paused and not entry._is_killed:
				var eased := Easing.ease(entry._ease_type, t)
				var val := lerpf(from, to, eased)
				on_update.call(val)
				if entry._on_update.is_valid():
					entry._on_update.call(),
		0.0, 1.0, maxf(duration, 0.0001)
	)

	entry._tween_id_for_kill = _bind_tween_callbacks(tween, entry)
	entry._is_playing = true
	return entry


## 泛型 Vector2 补间
func DoVector2(from: Vector2, to: Vector2, duration: float, on_update: Callable) -> TweenEntry:
	var entry := _create_entry()
	var tween := _create_godot_tween(entry)
	_set_delay(entry, tween)
	
	tween.tween_method(
		func(v: Vector2): 
			if not entry._is_paused and not entry._is_killed:
				on_update.call(v)
				if entry._on_update.is_valid(): entry._on_update.call(),
		from, to, duration
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_LINEAR)
	
	entry._tween_id_for_kill = _bind_tween_callbacks(tween, entry)
	entry._is_playing = true
	return entry


## 泛型 Color 补间
func DoColor(from: Color, to: Color, duration: float, on_update: Callable) -> TweenEntry:
	var entry := _create_entry()
	var tween := _create_godot_tween(entry)
	
	_set_delay(entry, tween)
	
	tween.tween_method(
		func(v: Color):
			if not entry._is_paused and not entry._is_killed:
				on_update.call(v)
				if entry._on_update.is_valid(): entry._on_update.call(),
		from, to, duration
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_LINEAR)
	
	entry._tween_id_for_kill = _bind_tween_callbacks(tween, entry)
	entry._is_playing = true
	return entry


# =============================================================================
# ---- 属性补间（对标 DOTween Property shortcuts）----
# =============================================================================

## 对节点属性做补间 —— 对标 transform.DOMove()
func DoProperty(target: Object, property: StringName, final_val: Variant, duration: float) -> TweenEntry:
	var entry := _create_entry()
	entry.target = target
	var tween := _create_godot_tween(entry)
	_set_delay(entry, tween)
	
	var prop_tween := tween.tween_property(target, property, final_val, duration)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_LINEAR)
	
	_bind_tween_callbacks(tween, entry)
	entry._tween_id_for_kill = _bind_final_callback(tween, entry)
	entry._is_playing = true
	
	# 应用循环
	if entry._loops > 1 or entry._loops < 0:
		var loop_count := entry._loops if entry._loops > 0 else 0
		prop_tween.set_loops(loop_count)
	
	return entry


## DoMove —— 移动节点到目标位置
func DoMove(target: Node2D, to: Vector2, duration: float) -> TweenEntry:
	return DoProperty(target, &"position", to, duration)


## DoMoveX —— 仅移动 X
func DoMoveX(target: Node2D, to: float, duration: float) -> TweenEntry:
	return DoProperty(target, &"position:x", to, duration)


## DoMoveY —— 仅移动 Y
func DoMoveY(target: Node2D, to: float, duration: float) -> TweenEntry:
	return DoProperty(target, &"position:y", to, duration)


## DOJump —— 抛物跳动画，对标 transform.DOJump()
## [param end_value]: 终点位置
## [param jump_power]: 跳跃高度（像素）
## [param num_jumps]: 跳跃段数，默认 1
## [param duration]: 总持续时间
func DoJump(target: Node2D, end_value: Vector2, jump_power: float, num_jumps: int, duration: float) -> TweenEntry:
	var entry := _create_entry()
	entry.target = target
	var tween := _create_godot_tween(entry)
	_set_delay(entry, tween)
	
	var start_pos := target.position
	var total_distance := end_value - start_pos
	var segment_duration := duration / float(num_jumps)
	
	for j in range(num_jumps):
		var seg_start := start_pos + total_distance * (float(j) / float(num_jumps))
		var seg_end := start_pos + total_distance * (float(j + 1) / float(num_jumps))
		
		# 用自定义方法实现抛物线：沿线性移动 + 垂直偏移（y = -4 * jump_power * (t - 0.5)^2 + jump_power）
		tween.tween_method(
			func(t: float):
				if is_instance_valid(target):
					var x := lerpf(seg_start.x, seg_end.x, t)
					var y_linear := lerpf(seg_start.y, seg_end.y, t)
					var parabola := -4.0 * jump_power * (t - 0.5) * (t - 0.5) + jump_power
					target.position = Vector2(x, y_linear - parabola),
			0.0, 1.0, segment_duration
		)
	
	_bind_tween_callbacks(tween, entry)
	entry._tween_id_for_kill = _bind_final_callback(tween, entry)
	entry._is_playing = true
	return entry


## DoLocalMove —— 局部坐标移动，对标 transform.DOLocalMove()
func DoLocalMove(target: Node2D, to: Vector2, duration: float) -> TweenEntry:
	return DoProperty(target, &"position", to, duration)


## DoScale —— 缩放节点
func DoScale(target: Node2D, to: Vector2, duration: float) -> TweenEntry:
	return DoProperty(target, &"scale", to, duration)


## DoRotate —— 旋转节点（度）
func DoRotate(target: Node2D, to: float, duration: float) -> TweenEntry:
	return DoProperty(target, &"rotation_degrees", to, duration)


## DoFade —— 淡入淡出 CanvasItem（Sprite2D, Control 等）
func DoFade(target: CanvasItem, to: float, duration: float) -> TweenEntry:
	return DoProperty(target, &"modulate:a", to, duration)


## DoColor —— 颜色补间（作用于 modulate）
func DoColorTint(target: CanvasItem, to: Color, duration: float) -> TweenEntry:
	return DoProperty(target, &"modulate", to, duration)


## DoVolume —— 音量补间（AudioStreamPlayer）
func DoVolume(target: AudioStreamPlayer, to: float, duration: float) -> TweenEntry:
	return DoProperty(target, &"volume_db", to, duration)


# =============================================================================
# ---- Shake / Punch 效果（对标 DOTween.DOShake / DOPunch）----
# =============================================================================

## 震动位置 —— 对标 transform.DOShakePosition()
## [param duration]: 震动持续时间
## [param strength]: 震动强度（像素），Vector2 可分别设置 X/Y
## [param vibrato]: 震动频率（震荡次数），默认 10
## [param randomness]: 随机性 [0, 180]，默认 90
## [param fade_out]: 是否逐渐衰减到 0，默认 true
func DoShakePosition(target: Node2D, duration: float, strength: Vector2, vibrato: int = 10, randomness: float = 90.0, fade_out: bool = true) -> TweenEntry:
	var entry := _create_entry()
	entry.target = target
	var tween := _create_godot_tween(entry)
	_set_delay(entry, tween)
	
	var original_pos := target.position
	var total_steps := vibrato * 2  # 每个 vibrato 有来回两段
	var step_duration := duration / float(total_steps)
	
	for i in range(total_steps):
		var progress := float(i) / float(total_steps)
		var intensity := 1.0 - progress if fade_out else 1.0
		var rx := randf_range(-1.0, 1.0) * strength.x * intensity
		var ry := randf_range(-1.0, 1.0) * strength.y * intensity
		tween.tween_property(target, &"position", original_pos + Vector2(rx, ry), step_duration * 0.5)
		tween.tween_property(target, &"position", original_pos, step_duration * 0.5)
	
	_bind_tween_callbacks(tween, entry)
	entry._tween_id_for_kill = _bind_final_callback(tween, entry)
	entry._is_playing = true
	return entry


## Punch 位置 —— 对标 transform.DOPunchPosition()
## 先向指定方向冲过去，然后震荡回原位
func DoPunchPosition(target: Node2D, punch: Vector2, duration: float, vibrato: int = 10, elasticity: float = 1.0) -> TweenEntry:
	var entry := _create_entry()
	entry.target = target
	var tween := _create_godot_tween(entry)
	_set_delay(entry, tween)
	
	var original_pos := target.position
	var total_steps := vibrato * 2 + 1
	var step_duration := duration / float(total_steps)
	
	# 第一步：冲向 punch
	tween.tween_property(target, &"position", original_pos + punch, step_duration)
	
	for i in range(vibrato):
		var decay := pow(elasticity, float(i + 1))
		var offset := punch * decay
		if i % 2 == 0:
			offset = -offset
		tween.tween_property(target, &"position", original_pos + offset, step_duration)
	
	# 最后回到原位
	tween.tween_property(target, &"position", original_pos, step_duration)
	
	_bind_tween_callbacks(tween, entry)
	entry._tween_id_for_kill = _bind_final_callback(tween, entry)
	entry._is_playing = true
	return entry


# =============================================================================
# ---- Camera 专用快捷方法 ----
# =============================================================================

## 相机震动 —— 对标 Camera.DOShakePosition()
func DoCameraShake(camera: Camera2D, duration: float, strength: Vector2 = Vector2(10, 10), vibrato: int = 10, randomness: float = 90.0, fade_out: bool = true) -> TweenEntry:
	var entry := _create_entry()
	entry.target = camera
	var tween := _create_godot_tween(entry)
	_set_delay(entry, tween)
	
	var original_offset := camera.offset
	var total_steps := vibrato * 2
	var step_duration := duration / float(total_steps)
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	
	for i in range(total_steps):
		var progress := float(i) / float(total_steps)
		var intensity := 1.0 - progress if fade_out else 1.0
		var time_offset := float(i) * 0.5
		var ox := strength.x * intensity * noise.get_noise_1d(time_offset)
		var oy := strength.y * intensity * noise.get_noise_1d(time_offset + 100.0)
		tween.tween_property(camera, &"offset", Vector2(ox, oy), step_duration)
	tween.tween_property(camera, &"offset", original_offset, 0.01)
	
	_bind_tween_callbacks(tween, entry)
	entry._tween_id_for_kill = _bind_final_callback(tween, entry)
	entry._is_playing = true
	return entry


# =============================================================================
# ---- Sequence（对标 DOTween.Sequence）----
# =============================================================================

## 创建一个 Sequence
func Sequence() -> TweenEntry:
	var entry := _create_entry()
	entry.is_sequence = true
	return entry


## Append —— 追加一个补间到 Sequence 末尾（前一个结束后才开始）
func Append(seq: TweenEntry, tween_entry: TweenEntry) -> TweenEntry:
	assert(seq.is_sequence, "Append: 第一个参数必须是 Sequence")
	if seq.godot_tween == null:
		seq.godot_tween = _create_godot_tween(seq)
		_set_delay(seq, seq.godot_tween)
	if tween_entry.godot_tween != null:
		# 如果被加入的补间已经有自己的 tween，串联起来
		seq.godot_tween.tween_callback(func(): 
			if not tween_entry._is_killed: 
				tween_entry.godot_tween.play()
		)
		seq.godot_tween.tween_interval(tween_entry.godot_tween.get_total_elapsed_time())
	return seq


## Join —— 并行加入一个补间（与上一个同时开始）
func Join(seq: TweenEntry, tween_entry: TweenEntry) -> TweenEntry:
	assert(seq.is_sequence, "Join: 第一个参数必须是 Sequence")
	if seq.godot_tween == null:
		seq.godot_tween = _create_godot_tween(seq)
	if tween_entry.godot_tween != null:
		seq.godot_tween.parallel().tween_callback(func():
			if not tween_entry._is_killed:
				tween_entry.godot_tween.play()
		)
	return seq


## AppendInterval —— 追加一段等待时间
func AppendInterval(seq: TweenEntry, interval: float) -> TweenEntry:
	assert(seq.is_sequence, "AppendInterval: 第一个参数必须是 Sequence")
	if seq.godot_tween == null:
		seq.godot_tween = _create_godot_tween(seq)
		_set_delay(seq, seq.godot_tween)
	seq.godot_tween.tween_interval(interval)
	return seq


## AppendCallback —— 追加一个回调
func AppendCallback(seq: TweenEntry, callback: Callable) -> TweenEntry:
	assert(seq.is_sequence, "AppendCallback: 第一个参数必须是 Sequence")
	if seq.godot_tween == null:
		seq.godot_tween = _create_godot_tween(seq)
		_set_delay(seq, seq.godot_tween)
	seq.godot_tween.tween_callback(callback)
	return seq


## Insert —— 在指定时间点插入补间
func Insert(seq: TweenEntry, at_position: float, tween_entry: TweenEntry) -> TweenEntry:
	assert(seq.is_sequence, "Insert: 第一个参数必须是 Sequence")
	if seq.godot_tween == null:
		seq.godot_tween = _create_godot_tween(seq)
	seq.godot_tween.tween_interval(at_position)
	if tween_entry.godot_tween != null:
		seq.godot_tween.tween_callback(func():
			if not tween_entry._is_killed:
				tween_entry.godot_tween.play()
		)
	return seq


# =============================================================================
# ---- 虚拟补间（对标 DOTween.DOVirtual）----
# =============================================================================

## 延迟调用 —— 对标 DOVirtual.DelayedCall()
func DelayedCall(delay: float, callback: Callable, ignore_time_scale: bool = true) -> TweenEntry:
	var entry := _create_entry()
	var tween := _create_godot_tween(entry)
	tween.tween_interval(delay).set_ignore_time_scale(ignore_time_scale)
	tween.tween_callback(callback)
	_bind_tween_callbacks(tween, entry)
	entry._tween_id_for_kill = _bind_final_callback(tween, entry)
	entry._is_playing = true
	return entry


# =============================================================================
# ---- 链式设置（对标 DOTween.SetXxx）----
# =============================================================================

## 设置缓动类型
func SetEase(entry: TweenEntry, ease_type: Easing.Type) -> TweenEntry:
	entry._ease_type = ease_type
	return entry


## 设置延迟（秒）
func SetDelay(entry: TweenEntry, delay: float) -> TweenEntry:
	entry._delay = delay
	return entry


## 设置循环
## [param loops]: -1 = 无限循环, 0/1 = 播放一次, N = 循环 N 次
func SetLoops(entry: TweenEntry, loops: int, loop_type: LoopType = LoopType.RESTART) -> TweenEntry:
	entry._loops = loops
	entry._loop_type = loop_type
	return entry


## 设置是否自动 Kill（完成后自动释放）
func SetAutoKill(entry: TweenEntry, auto_kill: bool) -> TweenEntry:
	entry._auto_kill = auto_kill
	return entry


## 设置为相对模式（From 变体）
func SetRelative(entry: TweenEntry, is_relative: bool = true) -> TweenEntry:
	entry._is_relative = is_relative
	return entry


## 设置时间缩放
func SetTimeScale(entry: TweenEntry, scale: float) -> TweenEntry:
	entry._time_scale = scale
	return entry


## 设置更新模式
func SetUpdate(entry: TweenEntry, update_type: UpdateType) -> TweenEntry:
	entry._update_type = update_type
	return entry


# =============================================================================
# ---- 链式回调（对标 DOTween.OnXxx）----
# =============================================================================

func OnStart(entry: TweenEntry, callback: Callable) -> TweenEntry:
	entry._on_start = callback
	return entry

func OnUpdate(entry: TweenEntry, callback: Callable) -> TweenEntry:
	entry._on_update = callback
	return entry

func OnComplete(entry: TweenEntry, callback: Callable) -> TweenEntry:
	entry._on_complete = callback
	return entry

func OnKill(entry: TweenEntry, callback: Callable) -> TweenEntry:
	entry._on_kill = callback
	return entry

func OnPause(entry: TweenEntry, callback: Callable) -> TweenEntry:
	entry._on_pause = callback
	return entry

func OnPlay(entry: TweenEntry, callback: Callable) -> TweenEntry:
	entry._on_play = callback
	return entry

func OnStepComplete(entry: TweenEntry, callback: Callable) -> TweenEntry:
	entry._on_step_complete = callback
	return entry


# =============================================================================
# ---- 控制方法（对标 DOTween.Play/Pause/Kill/Complete...）----
# =============================================================================

## 播放
func Play(entry: TweenEntry) -> void:
	if entry._is_killed: return
	if entry.godot_tween:
		entry.godot_tween.play()
	entry._is_playing = true
	entry._is_paused = false
	if entry._on_play.is_valid(): entry._on_play.call()

## 暂停
func Pause(entry: TweenEntry) -> void:
	if entry._is_killed: return
	if entry.godot_tween:
		entry.godot_tween.pause()
	entry._is_paused = true
	if entry._on_pause.is_valid(): entry._on_pause.call()

## 终止（并可选触发 Complete）
func Kill(entry: TweenEntry, complete: bool = false) -> void:
	if entry._is_killed: return
	if complete:
		Complete(entry)
	else:
		if entry.godot_tween:
			entry.godot_tween.kill()
		entry._is_killed = true
		entry._is_playing = false
		if entry._on_kill.is_valid(): entry._on_kill.call()
		tween_killed.emit(entry.id)
		if entry._auto_kill:
			_tweens.erase(entry.id)

## 立即完成
func Complete(entry: TweenEntry) -> void:
	if entry._is_killed: return
	if entry.godot_tween:
		entry.godot_tween.custom_step(999.0)
		entry.godot_tween.kill()
	_complete_entry(entry)

## 倒带（回到起始状态）
func Rewind(entry: TweenEntry, include_delay: bool = true) -> void:
	if entry._is_killed: return
	if entry.godot_tween:
		entry.godot_tween.kill()
	entry._is_playing = false
	entry._is_paused = false
	if entry._on_kill.is_valid(): entry._on_kill.call()

## 重播
func Restart(entry: TweenEntry) -> void:
	if entry._is_killed: return
	if entry.godot_tween:
		entry.godot_tween.kill()
	entry.godot_tween = _create_godot_tween(entry)
	entry._is_playing = true
	entry._is_paused = false
	entry._is_complete = false
	Play(entry)

## 翻转（反向播放）
func Flip(entry: TweenEntry) -> void:
	if entry._is_killed: return
	if entry.godot_tween:
		if entry.godot_tween.is_running():
			# 简单实现：Kill 后不处理翻转
			entry.godot_tween.kill()
	# 翻转逻辑较复杂，需要重新构建 tween
	# Godot 内置 Tween 不支持直接反转，此处仅标记
	push_warning("[TweenService] Flip() 暂不完全支持，请使用 PlayBackwards 或重新创建补间")

## 跳转到指定时间点
func Goto(entry: TweenEntry, to: float, and_play: bool = false) -> void:
	if entry._is_killed: return
	if entry.godot_tween:
		entry.godot_tween.custom_step(to)
		if and_play:
			entry.godot_tween.play()

## 切换暂停状态
func TogglePause(entry: TweenEntry) -> void:
	if entry._is_paused:
		Play(entry)
	else:
		Pause(entry)


# =============================================================================
# ---- 静态筛选方法（对标 DOTween.KillAll / PauseAll 等）----
# =============================================================================

## 终止所有补间
func KillAll() -> void:
	for id in _tweens.keys():
		Kill(_tweens[id])

## 暂停所有补间
func PauseAll() -> void:
	for entry in _tweens.values():
		Pause(entry)

## 播放所有补间
func PlayAll() -> void:
	for entry in _tweens.values():
		Play(entry)

## 根据 target 终止补间
func KillByTarget(target: Object) -> void:
	for entry in _tweens.values():
		if entry.target == target:
			Kill(entry)


# =============================================================================
# ---- 内部方法 ----
# =============================================================================

func _create_entry() -> TweenEntry:
	_next_id += 1
	var entry := TweenEntry.new()
	entry.id = _next_id
	_tweens[entry.id] = entry
	tween_created.emit(entry.id)
	return entry


func _create_godot_tween(entry: TweenEntry) -> Tween:
	var tween := _node.create_tween()
	# 防止 Godot Tween 完成后自动释放（由 TweenService 管理生命周期）
	tween.set_loops(1)
	match entry._update_type:
		UpdateType.FIXED:
			tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		UpdateType.UNSCALED:
			tween.set_ignore_time_scale(true)
	entry.godot_tween = tween
	return tween


func _set_delay(entry: TweenEntry, tween: Tween) -> void:
	if entry._delay > 0.0:
		tween.tween_interval(entry._delay)


func _bind_final_callback(tween: Tween, entry: TweenEntry) -> StringName:
	tween.tween_callback(func(): _complete_entry(entry))
	return &""


func _bind_tween_callbacks(tween: Tween, entry: TweenEntry) -> StringName:
	tween.finished.connect(
		func():
			_complete_entry(entry),
		CONNECT_ONE_SHOT
	)
	if entry._on_start.is_valid():
		tween.tween_callback(func(): entry._on_start.call())
	return &""


func _complete_entry(entry: TweenEntry) -> void:
	if entry._is_killed or entry._is_complete:
		return
	entry._is_complete = true
	entry._is_playing = false
	if entry._on_complete.is_valid():
		entry._on_complete.call()
	tween_completed.emit(entry.id)
	if entry._auto_kill:
		entry._is_killed = true
		tween_killed.emit(entry.id)
		_tweens.erase(entry.id)
