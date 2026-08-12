extends CharacterBody2D

## 竞技场敌人实体。
##
## Health、Team、Hurtbox 与 ContactHitbox 全部在 arena_enemy.tscn 中组合。
## 接触攻击只与 Hurtbox 交互，不再查找或直接调用目标 Health。
class_name ArenaEnemy

#region 常量与信号
const SPEED := 88.0

## Health 确认死亡后发出，由关卡决定计分和归还对象池。
signal defeated(enemy: ArenaEnemy)
#endregion

#region 依赖与状态
## 场景中静态组合的生命、接触伤害和攻击间隔节点。
@onready var health: UFrameHealth = $HealthComponent
@onready var contact_hitbox: UFrameHitbox2D = $ContactHitbox
@onready var contact_timer: Timer = $ContactAttackTimer

## 每次从对象池取出后由关卡注入的追逐目标。
var target: Node2D
var _knockback := Vector2.ZERO
var _hit_flash := 0.0
var _spawn_progress := 0.0
var _motion_phase := randf() * TAU
var _spawn_tween: Tween
#endregion

#region 对象池回调
## UFramePool 生命周期钩子：取出时先清掉上一轮运行状态。
func _on_pool_acquire() -> void:
	target = null
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	contact_hitbox.reset_hits()

## 归还池后停止计时与动画；节点、组件和碰撞体本身都继续复用。
func _on_pool_release() -> void:
	contact_timer.stop()
	target = null
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	if _spawn_tween and _spawn_tween.is_valid():
		_spawn_tween.kill()
	_spawn_tween = null
#endregion

#region 生命周期
## 在物理帧追逐当前目标，并衰减击退和命中闪白。
func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var chase := global_position.direction_to(target.global_position) * SPEED
	velocity = chase + _knockback
	move_and_slide()
	_knockback = _knockback.move_toward(Vector2.ZERO, 620.0 * delta)
	_motion_phase += delta * 5.0
	_hit_flash = move_toward(_hit_flash, 0.0, delta * 7.0)
	queue_redraw()
#endregion

#region 激活与战斗反馈
## 对象从 EnemyPool 取出后，由竞技场注入本轮目标和出生点。
func activate(new_target: Node2D, spawn_position: Vector2) -> void:
	target = new_target
	global_position = spawn_position
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	_hit_flash = 0.0
	_spawn_progress = 0.0
	health.reset()
	contact_hitbox.source = self
	contact_hitbox.reset_hits()
	contact_timer.start()
	if _spawn_tween and _spawn_tween.is_valid():
		_spawn_tween.kill()
	_spawn_tween = create_tween()
	_spawn_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_spawn_tween.tween_property(self, "_spawn_progress", 1.0, 0.28)
	queue_redraw()

## 命中后根据子弹方向产生闪白与实际击退。
func apply_hit_feedback(direction: Vector2, force: float = 95.0) -> void:
	_knockback += direction.normalized() * force
	_hit_flash = 1.0
	queue_redraw()
#endregion

#region 组件信号
## 持续接触时，每 0.5 秒重新开启一次攻击窗口。
## 伤害仍由 [method UFrameHurtbox2D.receive_hit] 统一处理 Team、无敌时间和 Health。
func _on_contact_attack_timer_timeout() -> void:
	contact_hitbox.reset_hits()
	for area: Area2D in contact_hitbox.get_overlapping_areas():
		var hurtbox := area as UFrameHurtbox2D
		if hurtbox:
			hurtbox.receive_hit(contact_hitbox)

func _on_health_component_died(_source: Node) -> void:
	contact_timer.stop()
	defeated.emit(self)
#endregion

#region 程序化绘制
func _draw() -> void:
	var scale_factor := maxf(_spawn_progress, 0.05)
	var bob := sin(_motion_phase) * 1.2
	var body_color := Color.WHITE if _hit_flash > 0.0 else Color("#ff6272")
	draw_circle(Vector2(0, 17), 13.0 * scale_factor, Color(Color("#000000"), 0.22))
	draw_circle(Vector2(0, bob), 20.0 * scale_factor, Color(Color("#ff6272"), 0.10))
	draw_circle(Vector2(0, bob), 16.0 * scale_factor, body_color)
	draw_arc(Vector2(0, bob), 13.0 * scale_factor, 0.15, PI - 0.15, 18, Color("#ff9aa5"), 2.0)
	if _spawn_progress > 0.65:
		draw_circle(Vector2(-5, -3 + bob), 2.2, Color("#2b1017"))
		draw_circle(Vector2(5, -3 + bob), 2.2, Color("#2b1017"))
	if health and health.hp < health.max_hp:
		draw_rect(Rect2(-Vector2(18, 27), Vector2(36, 4)), Color("#28141a"), true)
		draw_rect(Rect2(-Vector2(18, 27), Vector2(36.0 * float(health.hp) / health.max_hp, 4)), Color("#66d9a0"), true)
#endregion
