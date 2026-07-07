extends CanvasLayer
class_name TransitionService

# TransitionService.gd
# 场景切换过渡服务，支持淡入淡出、黑屏等效果
# 挂载方式：设为 Autoload，名称 "TransitionService"
#
# 使用方式：
#   await TransitionService.fade_out()
#   get_tree().change_scene_to_file("res://xxx.tscn")
#   TransitionService.fade_in()

@onready var color_rect: ColorRect = $ColorRect


# ========== 配置 ==========
var fade_color: Color = Color.BLACK
var fade_duration: float = 0.4


# ========== 初始化 ==========
func _ready() -> void:
	# 确保最高层级
	layer = 9999
	# 初始透明
	if color_rect:
		color_rect.color = Color(fade_color.r, fade_color.g, fade_color.b, 0.0)
		color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


# ========== 公共方法 ==========

## 淡出（画面变黑），完成后触发 callback 或 await
func fade_out(duration: float = -1.0) -> void:
	var dur := duration if duration > 0.0 else fade_duration
	if color_rect == null:
		_create_color_rect()
	_start_tween(Color(fade_color.r, fade_color.g, fade_color.b, 0.0),
	             Color(fade_color.r, fade_color.g, fade_color.b, 1.0),
	             dur)
	await get_tree().create_timer(dur).timeout


## 淡入（画面恢复）
func fade_in(duration: float = -1.0) -> void:
	var dur := duration if duration > 0.0 else fade_duration
	if color_rect == null:
		_create_color_rect()
	_start_tween(Color(fade_color.r, fade_color.g, fade_color.b, 1.0),
	             Color(fade_color.r, fade_color.g, fade_color.b, 0.0),
	             dur)
	await get_tree().create_timer(dur).timeout


## 切换场景（自动完成淡出→切场景→淡入）
func change_scene(target: String, duration: float = -1.0) -> void:
	var dur := duration if duration > 0.0 else fade_duration
	await fade_out(dur)
	get_tree().change_scene_to_file(target)
	await fade_in(dur)


# ========== 内部方法 ==========

func _create_color_rect() -> void:
	color_rect = ColorRect.new()
	color_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color_rect.color = Color(fade_color.r, fade_color.g, fade_color.b, 0.0)
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(color_rect)


func _start_tween(from: Color, to: Color, duration: float) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	# 直接插值 Color，不用 property 路径
	# 用 modify 方式更可靠
	color_rect.modulate = from
	tween.tween_property(color_rect, "modulate", to, duration)
	tween.play()
