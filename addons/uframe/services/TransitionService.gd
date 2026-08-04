extends Node

## 可选全屏画面过渡服务
##
## 通过 [code]UFrame.transitions[/code] 使用，只负责全屏遮罩与过渡流程[br]
## 场景加载统一委托给 [UFrameSceneService]，不维护第二套加载状态
class_name UFrameTransition

#region 信号
## [b]场景过渡开始[/b][br][br]
## [param target] : 目标场景路径
signal transition_started(target: String)

## [b]场景过渡结束[/b][br]
## 场景切换失败时仍会撤下遮罩后发出[br][br]
## [param target] : 目标场景路径[br]
## [param succeeded] : 场景切换是否成功
signal transition_finished(target: String, succeeded: bool)
#endregion

#region 配置
## [b]默认遮罩颜色[/b]
var fade_color := Color("#080b12")

## [b]默认单向淡变时长[/b]
var fade_duration := 0.22
#endregion

#region 运行时状态
## [b]场景服务引用[/b][br]
## 由 [code]UFrame[/code] 初始化阶段注入
var scene_service: UFrameSceneService

## [b]遮罩画布层[/b]
var _layer: CanvasLayer

## [b]全屏遮罩[/b]
var _overlay: ColorRect

## [b]当前淡变动画[/b]
var _fade_tween: Tween

## [b]完整过渡状态[/b]
var _busy := false
#endregion

#region 生命周期
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
#endregion

#region 主要方法
## [b]配置默认过渡[/b][br][br]
## [param color] : 默认遮罩颜色[br]
## [param duration] : 默认单向淡变秒数
func configure(color := Color("#080b12"), duration := 0.22) -> void:
	fade_color = color
	fade_duration = maxf(duration, 0.0)

## [b]淡出至完全遮挡[/b][br][br]
## [param duration] : 淡变秒数，负数时使用默认值[br]
## [param color] : 遮罩颜色，红色分量为负数时使用默认值
func fade_out(duration := -1.0, color := Color(-1, 0, 0, 0)) -> void:
	await _fade_to(1.0, _resolve_duration(duration), _resolve_color(color))

## [b]淡入至完全透明[/b][br][br]
## [param duration] : 淡变秒数，负数时使用默认值[br]
## [param color] : 遮罩颜色，红色分量为负数时使用默认值
func fade_in(duration := -1.0, color := Color(-1, 0, 0, 0)) -> void:
	await _fade_to(0.0, _resolve_duration(duration), _resolve_color(color))

## [b]带过渡切换场景[/b][br]
## 淡出后普通切换并等待新场景就绪，再淡入[br]
## 过渡忙碌、场景服务不可用或切换失败时返回 [code]false[/code][br][br]
## [param target] : 目标场景路径[br]
## [param duration] : 单向淡变秒数，负数时使用默认值[br]
## [param color] : 遮罩颜色，红色分量为负数时使用默认值
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

## [b]带过渡异步切换场景[/b][br]
## 淡出后在线程中加载场景并淡入；进度回调范围为 [code]0.0[/code] 到 [code]1.0[/code][br][br]
## [param target] : 目标场景路径[br]
## [param duration] : 单向淡变秒数，负数时使用默认值[br]
## [param color] : 遮罩颜色，红色分量为负数时使用默认值[br]
## [param on_progress] : 可选的加载进度回调
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
#endregion

#region 查询方法
## [b]判断是否正在过渡[/b]
func is_busy() -> bool:
	return _busy
#endregion

#region 内部方法
## [b]执行遮罩淡变[/b][br]
## 已有淡变时先等待其完成，透明后恢复鼠标事件穿透[br][br]
## [param alpha] : 目标不透明度[br]
## [param duration] : 淡变秒数[br]
## [param color] : 遮罩颜色
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

## [b]确保全屏遮罩可用[/b][br]
## 首次调用时创建始终处理的顶层 [CanvasLayer] 与 [ColorRect]
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

## [b]解析淡变时长[/b][br][br]
## [param duration] : 请求时长，负数时使用默认值
func _resolve_duration(duration: float) -> float:
	return fade_duration if duration < 0.0 else maxf(duration, 0.0)

## [b]解析遮罩颜色[/b][br][br]
## [param color] : 请求颜色，红色分量为负数时使用默认值
func _resolve_color(color: Color) -> Color:
	return fade_color if color.r < 0.0 else color
#endregion
