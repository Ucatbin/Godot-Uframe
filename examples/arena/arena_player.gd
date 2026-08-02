class_name ArenaPlayer
extends CharacterBody2D

## 竞技场玩家实体。
##
## 打开 arena_player.tscn 可以直接看到战斗组件，以及 BehaviorManager 下的 Movement。
## 移动由并行行为负责；本脚本只保留瞄准和玩家视觉表现。

## 场景中的组件引用。节点名和类型都能在 Inspector 中直接确认。
@onready var health: UFrameHealth = $HealthComponent
@onready var aim_pivot: Node2D = $AimPivot
@onready var behaviors: UFrameBehaviorManager = $BehaviorManager

var controls_enabled := true
var aim_direction := Vector2.RIGHT
var _move_phase := 0.0
var _hit_flash := 0.0

func _process(delta: float) -> void:
	_move_phase += delta * (3.0 + velocity.length() * 0.025)
	_hit_flash = move_toward(_hit_flash, 0.0, delta * 5.5)
	queue_redraw()

## 更新炮管朝向，同时旋转场景中的 Muzzle 标记点。
func set_aim_direction(direction: Vector2) -> void:
	if direction.length_squared() <= 0.001:
		return
	aim_direction = direction.normalized()
	aim_pivot.rotation = aim_direction.angle()
	queue_redraw()

## 子弹出生位置来自场景中的 Marker2D，而不是主场景里的魔法数字。
func get_muzzle_position() -> Vector2:
	return ($AimPivot/Muzzle as Marker2D).global_position

## HealthComponent 的场景信号连接到这里，受伤表现不污染生命组件。
func _on_health_component_damaged(_amount: int, _source: Node) -> void:
	_hit_flash = 1.0
	queue_redraw()

func _draw() -> void:
	var moving := velocity.length_squared() > 20.0 * 20.0
	var bob := sin(_move_phase) * 1.3 if moving else sin(_move_phase * 0.35) * 0.45
	draw_ellipse_shadow(Vector2(0, 17), Vector2(18, 6), Color(Color("#000000"), 0.28))
	# 炮管先画，保证主体覆盖连接处。
	draw_line(aim_direction * 6.0 + Vector2(0, bob), aim_direction * 27.0 + Vector2(0, bob), Color("#9ed2ff"), 8.0)
	draw_circle(Vector2(0, bob), 20.0, Color(Color("#5ca8ff"), 0.14))
	draw_circle(Vector2(0, bob), 16.0, Color.WHITE if _hit_flash > 0.0 else Color("#4e9bed"))
	draw_arc(Vector2(0, bob), 12.0, -PI * 0.15, PI * 1.35, 22, Color("#b8e0ff"), 2.0)
	draw_circle(aim_direction * 5.0 + Vector2(0, bob), 4.0, Color("#f4fbff"))

func draw_ellipse_shadow(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 20:
		var angle := TAU * float(index) / 20.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)
