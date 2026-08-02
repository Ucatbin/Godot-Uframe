class_name UFrameTransition
extends Node

## 可选的全屏淡入淡出服务，通过 UFrame.transitions 使用。
##
## 本服务只负责画面遮罩；场景加载统一委托给 UFrameSceneService，避免维护两套加载状态机。

## 完整场景过渡开始和结束时发出。
signal transition_started(target: String)
signal transition_finished(target: String, succeeded: bool)

## 默认遮罩颜色。
var fade_color := Color("#080b12")
## 默认单向淡变时长。
var fade_duration := 0.22

var scene_service: UFrameSceneService
var _layer: CanvasLayer
var _overlay: ColorRect
var _fade_tween: Tween
var _busy := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## 修改默认颜色和时长。
func configure(color := Color("#080b12"), duration := 0.22) -> void:
	fade_color = color
	fade_duration = maxf(duration, 0.0)

## 淡到完全遮挡。
func fade_out(duration := -1.0, color := Color(-1, 0, 0, 0)) -> void:
	await _fade_to(1.0, _resolve_duration(duration), _resolve_color(color))

## 淡到完全透明。
func fade_in(duration := -1.0, color := Color(-1, 0, 0, 0)) -> void:
	await _fade_to(0.0, _resolve_duration(duration), _resolve_color(color))

## 淡出、普通切换场景、等待新场景就绪，再淡入。过渡忙碌或切换失败时返回 false。
func change_scene(target: String, duration := -1.0, color := Color(-1, 0, 0, 0)) -> bool:
	if _busy or scene_service == null:
		return false
	_busy = true
	transition_started.emit(target)
	var resolved_duration := _resolve_duration(duration)
	var resolved_color := _resolve_color(color)
	await _fade_to(1.0, resolved_duration, resolved_color)
	# 等待明确的成功或错误结果。即使场景切换超时，下面也会撤掉黑色遮罩。
	var error := await scene_service.change_scene_confirmed(target)
	await _fade_to(0.0, resolved_duration, resolved_color)
	_busy = false
	var succeeded := error == OK
	transition_finished.emit(target, succeeded)
	return succeeded

## 淡出、线程加载场景并淡入。进度回调范围为 0 到 1。
func change_scene_async(
	target: String,
	duration := -1.0,
	color := Color(-1, 0, 0, 0),
	on_progress: Callable = Callable()
) -> bool:
	if _busy or scene_service == null:
		return false
	_busy = true
	transition_started.emit(target)
	var resolved_duration := _resolve_duration(duration)
	var resolved_color := _resolve_color(color)
	await _fade_to(1.0, resolved_duration, resolved_color)
	var error := await scene_service.change_scene_async(target, on_progress)
	await _fade_to(0.0, resolved_duration, resolved_color)
	_busy = false
	var succeeded := error == OK
	transition_finished.emit(target, succeeded)
	return succeeded

## 当前是否正在执行完整场景过渡。
func is_busy() -> bool:
	return _busy

func _fade_to(alpha: float, duration: float, color: Color) -> void:
	_ensure_overlay()
	if _fade_tween and _fade_tween.is_valid():
		await _fade_tween.finished
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var target := Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0))
	if duration <= 0.0:
		_overlay.color = target
	else:
		_fade_tween = create_tween()
		_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_fade_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		_fade_tween.tween_property(_overlay, "color", target, duration)
		await _fade_tween.finished
		_fade_tween = null
	_overlay.color = target
	if is_zero_approx(target.a):
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ensure_overlay() -> void:
	if _overlay:
		return
	_layer = CanvasLayer.new()
	_layer.layer = 9999
	add_child(_layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(fade_color.r, fade_color.g, fade_color.b, 0.0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_overlay)

func _resolve_duration(duration: float) -> float:
	return fade_duration if duration < 0.0 else maxf(duration, 0.0)

func _resolve_color(color: Color) -> Color:
	return fade_color if color.r < 0.0 else color
