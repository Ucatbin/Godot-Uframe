extends CharacterBody2D

## 平台跳跃玩家实体。
##
## 本脚本只保存玩家共享的数据、更新输入状态，并提供动作与反馈原语。
## Idle / Run / Air 三个状态才真正负责修改速度、调用
## [method CharacterBody2D.move_and_slide] 和切换状态。
## 打开 platformer_player.tscn，就能直接在场景树中看到状态机与全部状态。
class_name PlatformerPlayer

#region 信号
## 玩家真正开始一次跳跃后发出。
signal jumped
## 玩家从空中接触地面后发出；[param impact_speed] 是碰撞前的向下速度。
signal landed(impact_speed: float)
## 玩家跌出关卡边界并完成复位后发出。
signal fell
#endregion

#region 配置
@export_category("移动参数")
## 地面最大水平速度。
@export var movement_speed := 235.0
## 地面加速度。
@export var ground_acceleration := 1650.0
## 空中加速度。
@export var air_acceleration := 980.0
## 向上的初始跳跃速度。
@export var jump_speed := -430.0
## 正常下落时的重力。
@export var gravity := 1120.0
## 土狼跳窗口时间。
@export var coyote_time := 0.11
## 提前松开跳跃键时限制上升速度，形成高低跳。
@export var jump_cut_speed := -160.0
## 按住跳跃键时减弱重力的窗口时间。
@export var jump_hold_time := 0.085
## 跳跃输入缓冲时长。
@export var jump_buffer_time := 0.13
#endregion

#region 场景引用
## 场景中静态挂载的状态机。
@onready var sm: UFrameStateMachine = $StateMachine
## 只承受表现缩放和旋转的视觉根节点。
@onready var visual_root: Node2D = $VisualRoot
## 身体多边形组件。
@onready var body_polygon: Polygon2D = $VisualRoot/Body
## 高光多边形组件。
@onready var highlight_polygon: Polygon2D = $VisualRoot/Highlight
#endregion

#region 运行时状态
## 由关卡根节点注入；池放在静止世界中，粒子不会跟随玩家继续移动。
var effect_pool: UFramePool
## 是否允许输入。
var controls_enabled := true
## 本物理帧读取到的水平输入，三个状态共同读取。
var move_axis := 0.0
## 本物理帧是否仍按住跳跃键。
var jump_held := false
## 本物理帧是否刚松开跳跃键。
var jump_released := false
## 当前剩余土狼时间。
var coyote_remaining := 0.0
## 当前剩余长按跳跃窗口。
var jump_hold_remaining := 0.0
## 玩家在本关的安全出生点。
var spawn_position := Vector2.ZERO

## 自上一次脚步粒子生成后累计的实际水平移动距离。
var _walk_distance := 0.0
## 行走上下起伏动画的循环相位。
var _run_phase := 0.0
## 仅作用于 VisualRoot 的临时挤压与拉伸比例。
var _visual_scale := Vector2.ONE
## 根据水平速度平滑计算的视觉倾斜角度。
var _visual_rotation := 0.0
## 当前负责将身体比例回弹至正常大小的 Tween；新动画开始时用于停止旧动画。
var _body_tween: Tween
#endregion

#region 生命周期
## 记录出生点、检查示例依赖，并同步连接状态变化。
func _ready() -> void:
	spawn_position = global_position
	if UFrame.input == null:
		push_error("[PlatformerPlayer] 本示例需要启用 UFrame Input 模块")
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	sm.connect_state_changed(_on_state_changed)

## 每个物理帧更新输入状态与跳跃时间窗口。
func _physics_process(delta: float) -> void:
	_update_input_state(delta)

## 每帧更新玩家视觉，并检查是否跌出关卡边界。
func _process(delta: float) -> void:
	_update_visual(delta)
	if global_position.y > get_viewport_rect().size.y + 90.0:
		reset_to_spawn()
		fell.emit()
#endregion

#region 主要方法
## 消耗缓冲并开始跳跃。
func begin_jump() -> void:
	_consume_buffered_jump()
	velocity.y = jump_speed
	jump_hold_remaining = jump_hold_time
	coyote_remaining = 0.0
	_emit_jump_feedback()
	jumped.emit()

## Run 状态在完成真实物理移动后调用，以实际位移决定脚步粒子。
func update_walk_feedback(previous_position: Vector2) -> void:
	if not is_on_floor() or absf(velocity.x) < 35.0:
		_walk_distance = 0.0
		return
	_walk_distance += absf(global_position.x - previous_position.x)
	var speed_ratio := clampf(absf(velocity.x) / movement_speed, 0.0, 1.0)
	var spacing := lerpf(21.0, 10.0, speed_ratio)
	if _walk_distance < spacing:
		return
	_walk_distance = fmod(_walk_distance, spacing)
	_spawn_dust(
		global_position + Vector2(-signf(velocity.x) * 8.0, 17.0),
		Color("#a7bdd2"),
		Vector2(-signf(velocity.x), -0.38).normalized(),
		4,
		35.0 + absf(velocity.x) * 0.12,
		38.0,
		velocity * 0.05
	)

## Idle / Air 进入时清除上一次奔跑的步距，避免再次奔跑立即喷出旧脚步。
func reset_walk_feedback() -> void:
	_walk_distance = 0.0

## Air 状态确认真实落地后调用。
func emit_land_feedback(impact_speed: float) -> void:
	_emit_land_feedback(impact_speed)
	landed.emit(impact_speed)

## 把玩家安全重置到出生点，并明确回到 Air，让状态负责重新落地。
func reset_to_spawn() -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	coyote_remaining = 0.0
	jump_hold_remaining = 0.0
	_visual_scale = Vector2.ONE
	sm.change_state(&"air")
	queue_redraw()
#endregion

#region 查询方法
## 判断是否可以进行跳跃。
func can_start_jump() -> bool:
	return controls_enabled and coyote_remaining > 0.0 and _has_buffered_jump()

## 当前长按跳跃窗口的比例，供 HUD 展示。
func get_jump_hold_ratio() -> float:
	if jump_hold_time <= 0.0:
		return 0.0
	return clampf(jump_hold_remaining / jump_hold_time, 0.0, 1.0)
#endregion

#region 内部方法
## 每个物理帧读取按键，并更新跳跃缓冲、土狼时间与长按跳跃窗口。
func _update_input_state(delta: float) -> void:
	move_axis = Input.get_axis(&"demo_move_left", &"demo_move_right") if controls_enabled else 0.0
	jump_held = controls_enabled and Input.is_action_pressed(&"demo_jump")
	jump_released = controls_enabled and Input.is_action_just_released(&"demo_jump")
	if controls_enabled and Input.is_action_just_pressed(&"demo_jump"):
		UFrame.input.buffer_action(&"platform_jump", jump_buffer_time)
	if is_on_floor():
		coyote_remaining = coyote_time
	else:
		coyote_remaining = maxf(coyote_remaining - delta, 0.0)
		jump_hold_remaining = maxf(jump_hold_remaining - delta, 0.0)

## 查询 UFrameInput 中是否仍保存着有效的跳跃输入。
func _has_buffered_jump() -> bool:
	return UFrame.input.is_action_buffered(&"platform_jump")

## 消耗跳跃缓冲。
func _consume_buffered_jump() -> void:
	UFrame.input.consume_buffer(&"platform_jump")
#endregion

#region 视觉
## 更新视觉根节点的位置、旋转与缩放。
func _update_visual(delta: float) -> void:
	_run_phase += delta * (5.0 + absf(velocity.x) * 0.035)
	_visual_rotation = lerpf(
		_visual_rotation,
		clampf(velocity.x / movement_speed, -1.0, 1.0) * 0.065,
		1.0 - exp(-12.0 * delta)
	)
	var bounce := absf(sin(_run_phase)) * 1.4 if sm.is_in_state(&"run") else 0.0
	visual_root.position = Vector2(0, 17 - bounce)
	visual_root.rotation = _visual_rotation
	# 只缩放 VisualRoot；CollisionShape2D 始终保持稳定尺寸。
	visual_root.scale = _visual_scale * 1.22

## 状态切换时同步玩家颜色；状态机负责立即补发初始状态，避免遗漏初始视觉。
func _on_state_changed(_previous: StringName, current: StringName) -> void:
	_apply_state_visual(current)

## 根据当前状态切换身体与高光颜色。
func _apply_state_visual(state: StringName) -> void:
	var color := Color("#5ca8ff")
	if state == &"run":
		color = Color("#66d9a0")
	elif state == &"air":
		color = Color("#ffca70")
	body_polygon.color = color
	highlight_polygon.color = color.lightened(0.18)

## 生成起跳尘埃、身体拉伸与轻量相机震动。
func _emit_jump_feedback() -> void:
	_spawn_dust(
		global_position + Vector2(0, 17),
		Color("#ffca70"),
		Vector2(-signf(velocity.x) * 0.22, 1.0).normalized(),
		12,
		82.0 + absf(velocity.x) * 0.08,
		64.0,
		Vector2(velocity.x * 0.14, 0)
	)
	_animate_body(Vector2(0.78, 1.20), 0.18)
	if UFrame.camera:
		UFrame.camera.add_trauma(0.08)

## 根据冲击速度生成尘埃、身体压缩与相机震动。
func _emit_land_feedback(impact_speed: float) -> void:
	var strength := clampf(impact_speed / 760.0, 0.25, 1.0)
	_spawn_dust(
		global_position + Vector2(0, 17),
		Color("#c6d9ec"),
		Vector2.UP,
		8 + int(10.0 * strength),
		75.0 + 90.0 * strength,
		78.0,
		Vector2(velocity.x * 0.20, 0)
	)
	_animate_body(Vector2(1.0 + 0.24 * strength, 1.0 - 0.24 * strength), 0.22)
	if UFrame.camera:
		UFrame.camera.add_trauma(0.10 + 0.12 * strength)

## 从关卡对象池取出并初始化一次尘埃特效。
func _spawn_dust(
	origin: Vector2,
	color: Color,
	direction: Vector2,
	amount: int,
	speed: float,
	spread: float,
	inherited_velocity: Vector2
) -> void:
	if effect_pool == null:
		return
	var effect := effect_pool.acquire() as DemoBurstEffect
	if effect:
		effect.burst(origin, color, direction, amount, speed, spread, Vector2(0, 250), 0.48, 2.6, inherited_velocity)

## 设置玩家身体形变，并用新 Tween 替换尚未结束的旧动画。
func _animate_body(target_scale: Vector2, duration: float) -> void:
	if _body_tween and _body_tween.is_valid():
		_body_tween.kill()
	_visual_scale = target_scale
	_body_tween = create_tween()
	_body_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_body_tween.tween_property(self, "_visual_scale", Vector2.ONE, duration)
#endregion
