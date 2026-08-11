extends Node2D

## 单屏平台跳跃示例
##
## 持久存在的 Camera、平台、Goal、Player、对象池与 HUD 全部摆在 tscn 中
## 本脚本只负责关卡流程编排、展示数据更新与低成本程序化远景绘制

#region 配置
## 示例通用 UI 样式工具
const UI := preload("res://examples/common/example_ui.gd")
## 示例选择菜单场景路径
const MENU_SCENE := "res://examples/example_browser.tscn"

## 跟随玩家并承载震动、缩放反馈的主相机
@onready var camera: Camera2D = %DemoCamera
## 关卡级粒子对象池；在 _ready() 中注入 Player
@onready var effect_pool: UFramePool = %EffectPool
## 玩家抵达后触发通关流程的区域
@onready var goal: Area2D = %Goal
## 终点旗帜主体
@onready var goal_flag: Polygon2D = %GoalFlag
## 终点呼吸光圈
@onready var goal_pulse: Polygon2D = %GoalPulse
## 平台跳跃玩家实体
@onready var player: PlatformerPlayer = %Player
## 标题与操作提示所在的主面板
@onready var main_panel: PanelContainer = %MainPanel
## 当前状态信息面板
@onready var state_panel: PanelContainer = %StatePanel
## 当前玩家状态文本
@onready var state_label: Label = %StateLabel
## 土狼时间、完成次数与对象池数据文本
@onready var detail_label: Label = %DetailLabel
## 长按跳跃剩余窗口进度条
@onready var jump_bar: ProgressBar = %JumpBar
## 临时关卡消息面板
@onready var message_panel: PanelContainer = %MessagePanel
## 临时关卡消息文本
@onready var message_label: Label = %MessageLabel
#endregion

#region 运行时状态
## 当前相机缩放动画；新反馈开始时用于停止旧动画
var camera_tween: Tween
## 本次运行已经抵达终点的次数
var completions := 0
## 程序化背景与终点动画共用的累计时间
var _world_time := 0.0
## 是否正在播放通关流程，避免终点区域重复触发
var _completing := false
## 是否已经开始返回菜单，避免重复请求场景切换
var _changing_scene := false
#endregion

#region 生命周期
## 注入关卡级依赖、连接玩法信号并初始化相机与界面
func _ready() -> void:
	# 为玩家注入依赖
	player.effect_pool = effect_pool
	player.jumped.connect(_on_player_jumped)
	player.landed.connect(_on_player_landed)
	player.fell.connect(_on_player_fell)
	# 为场景注入依赖
	goal.body_entered.connect(_on_goal_body_entered)

	_style_static_ui()
	get_viewport().size_changed.connect(queue_redraw)
	# 相机动画
	if UFrame.camera:
		UFrame.camera.set_camera(camera)
		UFrame.camera.configure_shake(Vector2(8, 6), 0.9, 3.0, 2.0)
	_show_message("A / D 移动 · 空格短按低跳、长按高跳 · 到达右上方旗帜", 3.5)

## 更新返回菜单输入、HUD 数据、程序化动画时间与相机前瞻跟随
func _process(delta: float) -> void:
	# 返回菜单输入
	if Input.is_action_just_pressed(&"ui_cancel"):
		_return_to_menu()
		return
	# 更新程序化动画
	_world_time += delta
	queue_redraw()
	_animate_goal()
	# 更新 HUD 数据
	state_label.text = "状态  %s" % _state_display_name(player.sm.get_current_state_name())
	jump_bar.value = player.get_jump_hold_ratio() * 100.0
	detail_label.text = "土狼时间 %.2fs  ·  完成 %d 次  ·  特效池 %d / %d" % [
		player.coyote_remaining,
		completions,
		effect_pool.get_active_count(),
		effect_pool.get_total_count(),
	]
	# 更新相机偏移
	var look_ahead := Vector2(player.velocity.x * 0.055, player.velocity.y * 0.018)
	var follow_weight := 1.0 - exp(-9.0 * delta)
	camera.position = camera.position.lerp(get_viewport_rect().size * 0.5 + look_ahead, follow_weight)
#endregion

#region 主要方法
## 玩家进入终点区域时启动通关流程
func _on_goal_body_entered(body: Node2D) -> void:
	if body == player:
		_complete_level()

## 通关结算
func _complete_level() -> void:
	if _completing:
		return
	_completing = true
	completions += 1
	# 锁定玩家
	player.controls_enabled = false
	player.velocity = Vector2.ZERO
	# 完成后反馈
	for direction in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		var effect := effect_pool.acquire() as DemoBurstEffect
		if effect:
			effect.burst(goal.global_position, Color("#66d9a0"), direction, 10, 145.0, 38.0, Vector2(0, 180), 0.72, 3.0)
	_show_message("到达旗帜！状态、输入与相机将在短暂停顿后复位", 0.85)
	if UFrame.camera:
		UFrame.camera.add_trauma(0.36)
	_animate_camera_zoom(Vector2(1.045, 1.045), 0.14)
	# 玩家重置
	await get_tree().create_timer(0.85).timeout
	player.reset_to_spawn()
	player.controls_enabled = true
	_completing = false
#endregion

#region 查询方法
## 将状态标识转换为 HUD 使用的双语显示名称
func _state_display_name(state: StringName) -> String:
	match state:
		&"idle": return "IDLE / 待机"
		&"run": return "RUN / 奔跑"
		&"air": return "AIR / 空中"
		_: return String(state).to_upper()
#endregion

#region 内部方法
## 返回示例选择菜单，并防止同一帧发起多次场景切换
func _return_to_menu() -> void:
	if _changing_scene:
		return
	_changing_scene = true
	if UFrame.transitions and await UFrame.transitions.change_scene(MENU_SCENE, 0.14):
		return
	get_tree().change_scene_to_file(MENU_SCENE)
#endregion

#region 视觉
## 使用绘制命令生成无需额外场景节点的星空、山体与云层
func _draw() -> void:
	# 星
	for index in 48:
		var point := Vector2((index * 83) % 1080 - 40, 80 + (index * 47) % 330)
		draw_circle(point, 1.2 + index % 2, Color(Color("#c6e1ff"), 0.42))
	draw_circle(Vector2(724, 128), 52.0, Color("#ffdc82"))
	draw_circle(Vector2(707, 114), 52.0, Color("#0d1726"))
	# 山
	draw_colored_polygon(PackedVector2Array([
		Vector2(-120, 520), Vector2(80, 330), Vector2(220, 470), Vector2(390, 290),
		Vector2(560, 475), Vector2(735, 320), Vector2(1080, 520),
	]), Color("#172941"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-120, 555), Vector2(160, 410), Vector2(330, 525), Vector2(520, 390),
		Vector2(700, 520), Vector2(875, 405), Vector2(1080, 550),
	]), Color("#20364d"))
	# 云
	for index in 4:
		var cloud_x := fmod(index * 260.0 + _world_time * (8.0 + index), 1120.0) - 80.0
		var cloud_y := 112.0 + index * 48.0
		draw_circle(Vector2(cloud_x, cloud_y), 20.0, Color(Color("#d7e9f7"), 0.08))
		draw_circle(Vector2(cloud_x + 22, cloud_y + 3), 16.0, Color(Color("#d7e9f7"), 0.08))
		draw_circle(Vector2(cloud_x - 19, cloud_y + 5), 13.0, Color(Color("#d7e9f7"), 0.08))

## 为场景中的固定 HUD 节点应用统一示例样式
func _style_static_ui() -> void:
	UI.apply_panel(main_panel, Color("#5ca8ff"), 13)
	UI.apply_panel(state_panel, Color("#66d9a0"), 13)
	UI.apply_panel(message_panel, Color("#5ca8ff"), 9)
	UI.style_label(%TitleLabel, 20)
	UI.style_chip(%ControlChip, Color("#5ca8ff"))
	UI.style_label(%JumpWindowLabel, 13, Color("#ffca70"))
	UI.style_progress_bar(jump_bar, Color("#ffca70"))
	UI.style_label(state_label, 17, Color("#66d9a0"))
	UI.style_label(detail_label, 12, UI.MUTED)
	UI.style_label(message_label, 14)

## 更新终点旗帜摆动与光圈呼吸动画
func _animate_goal() -> void:
	var wave := sin(_world_time * 4.0)
	goal_flag.rotation = wave * 0.045
	goal_flag.scale.x = 1.0 + wave * 0.055
	var pulse_scale := 0.88 + (sin(_world_time * 3.0) * 0.5 + 0.5) * 0.24
	goal_pulse.scale = Vector2.ONE * pulse_scale
	goal_pulse.modulate.a = 0.20 + (sin(_world_time * 3.0) * 0.5 + 0.5) * 0.20

## 跳跃时快速缩小镜头，再平滑回到正常缩放
func _on_player_jumped() -> void:
	_animate_camera_zoom(Vector2(0.978, 0.978), 0.09)

## 根据落地速度控制镜头冲击反馈强度
func _on_player_landed(impact_speed: float) -> void:
	var strength := clampf(impact_speed / 850.0, 0.0, 1.0)
	_animate_camera_zoom(Vector2.ONE + Vector2.ONE * 0.022 * strength, 0.07)

## 玩家跌落并复位后显示操作提示
func _on_player_fell() -> void:
	_show_message("跌落已自动复位；输入缓冲仍会正确清空", 1.4)

## 将相机缩放到目标值后回弹，并用新动画替换尚未结束的旧动画
func _animate_camera_zoom(target: Vector2, duration: float) -> void:
	if camera_tween and camera_tween.is_valid():
		camera_tween.kill()
	camera_tween = create_tween()
	camera_tween.tween_property(camera, "zoom", target, duration).set_trans(Tween.TRANS_QUAD)
	camera_tween.tween_property(camera, "zoom", Vector2.ONE, duration * 1.8).set_trans(Tween.TRANS_BACK)

## 显示一段临时消息，并在指定持续时间后淡出面板
func _show_message(text: String, duration: float) -> void:
	message_label.text = text
	var tween := create_tween()
	tween.tween_property(message_panel, "modulate:a", 1.0, 0.14)
	tween.tween_interval(duration)
	tween.tween_property(message_panel, "modulate:a", 0.0, 0.24)
#endregion
