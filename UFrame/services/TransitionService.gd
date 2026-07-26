extends CanvasLayer
class_name TransitionService

# TransitionService.gd
# 场景切换过渡服务，支持淡入淡出、黑屏、自定义颜色等效果
# 对标 DOTween 的视觉过渡思路
# 挂载方式：设为 Autoload，名称 "TransitionService"
#
# 使用方式：
#   # 基础用法
#   await TransitionService.fade_out()
#   get_tree().change_scene_to_file("res://xxx.tscn")
#   TransitionService.fade_in()
#
#   # 一键切场景
#   await TransitionService.change_scene("res://xxx.tscn", 0.5, Color.WHITE)
#
#   # 闪光过渡
#   await TransitionService.flash(Color.WHITE, 0.3)

@onready var color_rect: ColorRect = $ColorRect


# =============================================================================
# 配置
# =============================================================================
var fade_color: Color = Color.BLACK
var fade_duration: float = 0.4
var fade_ease: Easing.Type = Easing.Type.IN_OUT_SINE


# =============================================================================
# 初始化
# =============================================================================
func _ready() -> void:
	# 确保最高层级
	layer = 9999
	# 初始透明
	if color_rect:
		color_rect.color = Color(fade_color.r, fade_color.g, fade_color.b, 0.0)
		color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


# =============================================================================
# 公共方法 ———— 淡入淡出
# =============================================================================

## 淡出（画面变黑/变指定颜色）
## [param duration]: 持续时间（-1 使用默认值）
## [param color]: 目标颜色（-1 使用默认值，即 Color(-1,0,0,0) 表示用默认）
func fade_out(duration: float = -1.0, color: Color = Color(-1, 0, 0, 0)) -> void:
	var dur := duration if duration > 0.0 else fade_duration
	var col := fade_color if color.r < 0.0 else color
	if color_rect == null:
		_create_color_rect()
	
	await _do_fade(
		Color(col.r, col.g, col.b, 0.0),
		Color(col.r, col.g, col.b, 1.0),
		dur,
		fade_ease
	)


## 淡入（画面恢复透明）
func fade_in(duration: float = -1.0, color: Color = Color(-1, 0, 0, 0)) -> void:
	var dur := duration if duration > 0.0 else fade_duration
	var col := fade_color if color.r < 0.0 else color
	if color_rect == null:
		_create_color_rect()
	
	await _do_fade(
		Color(col.r, col.g, col.b, 1.0),
		Color(col.r, col.g, col.b, 0.0),
		dur,
		fade_ease
	)


# =============================================================================
# 公共方法 ———— 场景切换
# =============================================================================

## 切换场景（自动完成淡出→切场景→淡入）
func change_scene(target: String, duration: float = -1.0, color: Color = Color(-1, 0, 0, 0)) -> void:
	var dur := duration if duration > 0.0 else fade_duration
	var col := fade_color if color.r < 0.0 else color
	await fade_out(dur, col)
	get_tree().change_scene_to_file(target)
	await fade_in(dur, col)


## 切换场景（带加载进度回调）
func change_scene_async(target: String, duration: float = -1.0, color: Color = Color(-1, 0, 0, 0), on_progress: Callable = Callable()) -> void:
	var dur := duration if duration > 0.0 else fade_duration
	var col := fade_color if color.r < 0.0 else color
	await fade_out(dur, col)
	
	# 异步加载
	var loader := ResourceLoader.load_threaded_request(target)
	if loader != OK:
		push_error("[TransitionService] 无法加载场景: %s" % target)
		await fade_in(dur, col)
		return
	
	var progress_arr: Array[float] = []
	while true:
		var status := ResourceLoader.load_threaded_get_status(target, progress_arr)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				if on_progress.is_valid():
					on_progress.call(progress_arr[0])
			ResourceLoader.THREAD_LOAD_LOADED:
				if on_progress.is_valid():
					on_progress.call(1.0)
				var scene := ResourceLoader.load_threaded_get(target) as PackedScene
				if scene:
					get_tree().change_scene_to_packed(scene)
				break
			ResourceLoader.THREAD_LOAD_FAILED:
				push_error("[TransitionService] 场景加载失败: %s" % target)
				break
		await get_tree().process_frame
	
	await fade_in(dur, col)


# =============================================================================
# 公共方法 ———— 特殊过渡效果
# =============================================================================

## 闪光过渡（快速闪白/闪黑 → 切换场景 → 恢复）
func flash(flash_color: Color = Color.WHITE, duration: float = 0.3) -> void:
	if color_rect == null:
		_create_color_rect()
	
	var half_dur := duration * 0.5
	await _do_fade(Color(flash_color.r, flash_color.g, flash_color.b, 0.0), Color(flash_color.r, flash_color.g, flash_color.b, 1.0), half_dur, Easing.Type.OUT_EXPO)
	await _do_fade(Color(flash_color.r, flash_color.g, flash_color.b, 1.0), Color(flash_color.r, flash_color.g, flash_color.b, 0.0), half_dur, Easing.Type.IN_EXPO)


## 闪光过渡 + 切场景
func flash_change_scene(target: String, flash_color: Color = Color.WHITE, duration: float = 0.3) -> void:
	var half_dur := duration * 0.5
	await _do_fade(Color(flash_color.r, flash_color.g, flash_color.b, 0.0), Color(flash_color.r, flash_color.g, flash_color.b, 1.0), half_dur, Easing.Type.OUT_EXPO)
	get_tree().change_scene_to_file(target)
	await _do_fade(Color(flash_color.r, flash_color.g, flash_color.b, 1.0), Color(flash_color.r, flash_color.g, flash_color.b, 0.0), half_dur, Easing.Type.IN_EXPO)


# =============================================================================
# 公共方法 ———— 配置
# =============================================================================

## 设置默认配置
func configure(color: Color = Color.BLACK, duration: float = 0.4, ease_type: Easing.Type = Easing.Type.IN_OUT_SINE) -> void:
	fade_color = color
	fade_duration = duration
	fade_ease = ease_type


# =============================================================================
# 内部方法
# =============================================================================

func _create_color_rect() -> void:
	color_rect = ColorRect.new()
	color_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color_rect.color = Color(fade_color.r, fade_color.g, fade_color.b, 0.0)
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(color_rect)


func _do_fade(from: Color, to: Color, duration: float, ease_type: Easing.Type) -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_LINEAR)
	
	# 用自定义缓动曲线手动插值
	var elapsed := 0.0
	tween.tween_method(
		func(t: float):
			elapsed += get_process_delta_time()
			var progress := clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
			var eased := Easing.ease(ease_type, progress)
			color_rect.modulate = from.lerp(to, eased),
		0.0, 1.0, duration
	)
	await tween.finished

	# 确保最终状态
	color_rect.modulate = to
