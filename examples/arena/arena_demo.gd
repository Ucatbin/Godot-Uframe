extends Node2D

## 俯视角生存示例。
##
## 打开 arena_demo.tscn 即可看到玩家实体、三个对象池、相机和完整 HUD。
## 本脚本只负责游戏流程编排；实体由 .tscn 定义，组件不在代码中动态创建。

const UI := preload("res://examples/common/example_ui.gd")
const MENU_SCENE := "res://examples/example_browser.tscn"

@onready var player: ArenaPlayer = $World/Player
@onready var enemy_pool: UFramePool = $World/EnemyPool
@onready var bullet_pool: UFramePool = $World/BulletPool
@onready var effect_pool: UFramePool = $World/EffectPool
@onready var camera: Camera2D = $MainCamera

@onready var main_panel: PanelContainer = $HUD/TopMargin/TopRow/MainPanel
@onready var stats_panel: PanelContainer = $HUD/TopMargin/TopRow/StatsPanel
@onready var title_label: Label = $HUD/TopMargin/TopRow/MainPanel/MainColumn/Heading/Title
@onready var controls_chip: Label = $HUD/TopMargin/TopRow/MainPanel/MainColumn/Heading/ControlsChip
@onready var hp_bar: ProgressBar = $HUD/TopMargin/TopRow/MainPanel/MainColumn/HealthRow/HealthBar
@onready var hp_label: Label = $HUD/TopMargin/TopRow/MainPanel/MainColumn/HealthRow/HealthLabel
@onready var score_label: Label = $HUD/TopMargin/TopRow/StatsPanel/StatsColumn/ScoreRow/ScoreLabel
@onready var threat_label: Label = $HUD/TopMargin/TopRow/StatsPanel/StatsColumn/ScoreRow/ThreatLabel
@onready var runtime_label: Label = $HUD/TopMargin/TopRow/StatsPanel/StatsColumn/RuntimeLabel
@onready var message_panel: PanelContainer = $HUD/MessagePanel
@onready var message_label: Label = $HUD/MessagePanel/MessageLabel

var enemies: Array[ArenaEnemy] = []
var score := 0
var elapsed := 0.0
var spawn_timer := 0.0
var shoot_timer := 0.0
var camera_tween: Tween
var message_tween: Tween
var _ended := false
var _changing_scene := false

func _ready() -> void:
	_style_hud()
	var movement := player.behaviors.get_behavior(&"Movement") as ArenaPlayerMovementBehavior
	if movement:
		movement.dust_requested.connect(_on_player_dust_requested)
	player.health.died.connect(_on_player_died)
	player.health.damaged.connect(_on_player_damaged)
	get_viewport().size_changed.connect(queue_redraw)
	if UFrame.camera:
		UFrame.camera.set_camera(camera)
		UFrame.camera.configure_shake(Vector2(10, 7), 1.1, 2.8, 2.0)
	for _index in 6:
		_spawn_enemy()
	_show_temporary_message("移动起来：扬尘由实际位移触发，实体与特效均来自场景对象池", 3.6)

func _process(delta: float) -> void:
	if Input.is_action_just_pressed(&"ui_cancel"):
		_return_to_menu()
		return
	if _ended:
		return
	elapsed += delta
	spawn_timer -= delta
	shoot_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = maxf(1.08 - elapsed * 0.008, 0.48)
		_spawn_enemy()
	if shoot_timer <= 0.0:
		shoot_timer = 0.22
		_shoot_nearest()
	_update_hud()
	var look_ahead := player.velocity * 0.040
	var follow_weight := 1.0 - exp(-8.5 * delta)
	camera.position = camera.position.lerp(get_viewport_rect().size * 0.5 + look_ahead, follow_weight)

func _draw() -> void:
	var size := get_viewport_rect().size
	var overscan := 110.0
	draw_rect(Rect2(Vector2(-overscan, -overscan), size + Vector2.ONE * overscan * 2.0), Color("#0b111c"))
	var grid_color := Color(Color("#233044"), 0.55)
	for x in range(-96, int(size.x) + 144, 48):
		draw_line(Vector2(x, -overscan), Vector2(x, size.y + overscan), grid_color, 1.0)
	for y in range(-96, int(size.y) + 144, 48):
		draw_line(Vector2(-overscan, y), Vector2(size.x + overscan, y), grid_color, 1.0)
	var center := size * 0.5
	draw_circle(center, 215.0, Color(Color("#5ca8ff"), 0.025))
	draw_arc(center, 215.0, 0.0, TAU, 72, Color(Color("#5ca8ff"), 0.12), 2.0)
	draw_arc(center, 118.0, 0.0, TAU, 48, Color(Color("#ff6b7a"), 0.08), 1.0)

## 三个池的 instance_created 信号在场景中连接，因此预热实例也只绑定一次信号。
func _on_enemy_pool_instance_created(instance: Node) -> void:
	var enemy := instance as ArenaEnemy
	if enemy and not enemy.defeated.is_connected(_on_enemy_defeated):
		enemy.defeated.connect(_on_enemy_defeated)

func _on_bullet_pool_instance_created(instance: Node) -> void:
	var bullet := instance as ArenaBullet
	if bullet == null:
		return
	var callback := _on_bullet_hit.bind(bullet)
	if not bullet.hit_confirmed.is_connected(callback):
		bullet.hit_confirmed.connect(callback)

func _spawn_enemy() -> void:
	_prune_enemies()
	if enemies.size() >= 40 or not is_instance_valid(player):
		return
	var enemy := enemy_pool.acquire() as ArenaEnemy
	if enemy == null:
		return
	var size := get_viewport_rect().size
	var side := randi_range(0, 3)
	var spawn_position: Vector2
	match side:
		0: spawn_position = Vector2(randf_range(25, size.x - 25), 102)
		1: spawn_position = Vector2(size.x - 22, randf_range(105, size.y - 25))
		2: spawn_position = Vector2(randf_range(25, size.x - 25), size.y - 22)
		_: spawn_position = Vector2(22, randf_range(105, size.y - 25))
	enemy.activate(player, spawn_position)
	enemies.append(enemy)
	_spawn_burst(enemy.global_position, Color("#ff6b7a"), Vector2.UP, 10, 72.0, 180.0, Vector2.ZERO)

func _shoot_nearest() -> void:
	_prune_enemies()
	var nearest: ArenaEnemy
	var nearest_distance := INF
	for candidate in enemies:
		var distance := player.global_position.distance_squared_to(candidate.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate
	if nearest == null:
		return
	var direction := player.global_position.direction_to(nearest.global_position)
	player.set_aim_direction(direction)
	var bullet := bullet_pool.acquire() as ArenaBullet
	if bullet == null:
		return
	var muzzle_position := player.get_muzzle_position()
	bullet.launch(muzzle_position, direction, player)
	_spawn_burst(muzzle_position, Color("#ffca70"), direction, 6, 78.0, 24.0, player.velocity * 0.12)
	if UFrame.camera:
		UFrame.camera.add_trauma(0.012)

func _on_bullet_hit(target: Node, applied_damage: int, bullet: ArenaBullet) -> void:
	var enemy := target.get_parent() as ArenaEnemy
	if enemy:
		enemy.apply_hit_feedback(bullet.direction, 82.0 + applied_damage * 15.0)
		_spawn_burst(enemy.global_position, Color("#ff9a63"), bullet.direction, 11, 118.0, 48.0, bullet.direction * 25.0)
	if UFrame.camera:
		UFrame.camera.add_trauma(0.055)
	_animate_camera_zoom(Vector2(1.012, 1.012), 0.035)

func _on_player_dust_requested(origin: Vector2, movement_velocity: Vector2) -> void:
	_spawn_burst(origin, Color("#7f97b2"), -movement_velocity.normalized(), 4, 42.0 + movement_velocity.length() * 0.08, 38.0, movement_velocity * 0.04)

func _on_player_damaged(_amount: int, source: Node) -> void:
	var direction := Vector2.UP
	if source is Node2D:
		direction = (source as Node2D).global_position.direction_to(player.global_position)
	_spawn_burst(player.global_position, Color("#ff6272"), direction, 18, 145.0, 62.0, player.velocity * 0.18)
	if UFrame.camera:
		UFrame.camera.add_trauma(0.28)

func _on_enemy_defeated(enemy: ArenaEnemy) -> void:
	if enemy not in enemies:
		return
	enemies.erase(enemy)
	score += 1
	_spawn_burst(enemy.global_position, Color("#ff6b7a"), Vector2.UP, 20, 150.0, 180.0, enemy.velocity * 0.12)
	_show_floating_text(enemy.global_position, "+1")
	if score % 10 == 0:
		_show_temporary_message("威胁升级：生成间隔正在缩短", 1.6)
	# Health.died 来自物理碰撞回调，延迟归还以安全关闭所有后代碰撞组件。
	call_deferred("_release_enemy", enemy)

func _release_enemy(enemy: ArenaEnemy) -> void:
	if is_instance_valid(enemy):
		enemy_pool.release(enemy)

func _on_player_died(_source: Node) -> void:
	if _ended:
		return
	_ended = true
	player.controls_enabled = false
	_show_temporary_message("本轮结束 · 即将重新开始", 1.0)
	if UFrame.camera:
		UFrame.camera.add_trauma(0.65)
	await get_tree().create_timer(0.85).timeout
	get_tree().reload_current_scene()

func _spawn_burst(
	position: Vector2,
	color: Color,
	direction: Vector2,
	amount: int,
	speed: float,
	spread: float,
	inherited_velocity: Vector2
) -> void:
	var effect := effect_pool.acquire() as DemoBurstEffect
	if effect:
		effect.burst(position, color, direction, amount, speed, spread, Vector2(0, 90), 0.42, 2.5, inherited_velocity)

## 浮字是低频、短寿命的表现节点，保留运行时创建以展示合理边界。
func _show_floating_text(world_position: Vector2, text: String) -> void:
	var label := UI.make_label(text, 18, Color("#ffca70"))
	label.position = world_position - Vector2(18, 30)
	label.z_index = 20
	add_child(label)
	var tween := create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 30.0, 0.55)
	tween.tween_property(label, "modulate:a", 0.0, 0.55)
	tween.chain().tween_callback(label.queue_free)

func _show_temporary_message(text: String, duration: float) -> void:
	message_label.text = text
	if message_tween and message_tween.is_valid():
		message_tween.kill()
	message_tween = create_tween()
	message_tween.tween_property(message_panel, "modulate:a", 1.0, 0.16)
	message_tween.tween_interval(duration)
	message_tween.tween_property(message_panel, "modulate:a", 0.0, 0.25)

func _update_hud() -> void:
	hp_bar.max_value = player.health.max_hp
	hp_bar.value = player.health.hp
	hp_label.text = "生命  %d / %d" % [player.health.hp, player.health.max_hp]
	score_label.text = "击败  %d" % score
	var threat := 1 + int(elapsed / 15.0)
	threat_label.text = "威胁 %d" % threat
	runtime_label.text = "敌人 %d/%d · 子弹 %d/%d · 特效 %d/%d · Esc 返回" % [
		enemy_pool.get_active_count(),
		enemy_pool.get_total_count(),
		bullet_pool.get_active_count(),
		bullet_pool.get_total_count(),
		effect_pool.get_active_count(),
		effect_pool.get_total_count(),
	]

func _prune_enemies() -> void:
	for index in range(enemies.size() - 1, -1, -1):
		if not is_instance_valid(enemies[index]) or enemies[index].is_queued_for_deletion():
			enemies.remove_at(index)

func _animate_camera_zoom(target: Vector2, duration: float) -> void:
	if camera_tween and camera_tween.is_valid():
		camera_tween.kill()
	camera_tween = create_tween()
	camera_tween.tween_property(camera, "zoom", target, duration)
	camera_tween.tween_property(camera, "zoom", Vector2.ONE, duration * 2.5)

## 节点由场景定义，代码只补充运行时 StyleBox 主题资源。
func _style_hud() -> void:
	UI.apply_panel(main_panel, Color("#ff6b7a"), 13)
	UI.apply_panel(stats_panel, Color("#5ca8ff"), 13)
	UI.apply_panel(message_panel, Color("#5ca8ff"), 10)
	UI.style_label(title_label, 20)
	UI.style_chip(controls_chip, Color("#ff6b7a"))
	UI.style_label(hp_label, 13, UI.MUTED)
	UI.style_progress_bar(hp_bar, Color("#66d9a0"))
	UI.style_label(score_label, 17, Color("#ffca70"))
	UI.style_chip(threat_label, Color("#ff6b7a"))
	UI.style_label(runtime_label, 13, UI.MUTED)
	UI.style_label(message_label, 14, UI.TEXT)
	message_panel.modulate.a = 0.0

func _return_to_menu() -> void:
	if _changing_scene:
		return
	_changing_scene = true
	if UFrame.transitions and await UFrame.transitions.change_scene(MENU_SCENE, 0.14):
		return
	get_tree().change_scene_to_file(MENU_SCENE)
