class_name UFrameHitbox2D
extends Area2D

## 攻击判定框，只保存“如何造成伤害”的数据。
##
## 将它挂到武器、子弹等攻击 Area2D 上，并添加 CollisionShape2D。[br]
## UFrameHurtbox2D 检测到本组件后负责把伤害传递给 UFrameHealth。[br]
## Hitbox 自己不监听碰撞信号，这样可以避免双方同时结算造成重复伤害。

## 每次命中造成的基础伤害。
@export var damage := 10
## 命中成功后是否销毁 Hitbox 的父节点，常用于一次性子弹。
@export var destroy_on_hit := false
## 一次激活期间，同一个 Hurtbox 是否只能命中一次。
@export var hit_once_per_activation := true
## 伤害来源。未手动设置时默认使用父节点。
var source: Node
## 本次激活已经命中的 Hurtbox 集合。
var _hit_targets: Dictionary = {}

## 目标真正扣除生命后发出，适合在局部生成命中特效或伤害数字。
signal hit_confirmed(target: Node, applied_damage: int)

func _ready() -> void:
	if source == null:
		source = get_parent()

## 判断当前激活期间是否还可以命中目标。
func can_hit(target: Node) -> bool:
	return is_instance_valid(target) and (not hit_once_per_activation or not _hit_targets.has(target))

## 记录一次成功命中。只有 Hurtbox 确认伤害生效后才应调用。
func mark_hit(target: Node, applied_damage := damage) -> void:
	_hit_targets[target] = true
	hit_confirmed.emit(target, applied_damage)
	if destroy_on_hit and is_instance_valid(get_parent()):
		get_parent().queue_free()

## 清除命中记录。开始一次新的攻击窗口时应调用。
func reset_hits() -> void:
	_hit_targets.clear()

## UFramePool 自动识别的生命周期钩子。
func _on_pool_acquire() -> void:
	reset_hits()
