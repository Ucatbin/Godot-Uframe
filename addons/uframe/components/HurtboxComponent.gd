class_name UFrameHurtbox2D
extends Area2D

## 受击判定框，是 Hitbox/Hurtbox 碰撞系统的唯一伤害结算入口。
##
## 推荐场景结构：[br]
## [codeblock]
## Player
## ├── HealthComponent       # UFrameHealth
## └── HurtboxComponent      # UFrameHurtbox2D
##     └── CollisionShape2D
## [/codeblock]
## 默认会在同级位置查找名为 HealthComponent 的 UFrameHealth。结构不同时可修改 Health Path。

## 指向本实体 UFrameHealth 节点的路径。
@export var health_path: NodePath = ^"../HealthComponent"
## 是否在双方都有 UFrameTeam 时过滤友军伤害。
## 任意一方没有 Team 时仍允许伤害，因此 Health/Hitbox 可以继续独立使用。
@export var use_team_filter := true
## 指向本实体 UFrameTeam 的可选路径。留空时按 TeamComponent 命名约定查找。
@export var team_component_path: NodePath = ^"../TeamComponent"
## 缓存生命组件，避免每次碰撞时重复查找节点。
var _health: UFrameHealth
## 可选阵营组件缓存。不存在时不会产生警告，也不会阻止伤害。
var _team: UFrameTeam

func _ready() -> void:
	_health = get_node_or_null(health_path) as UFrameHealth
	if use_team_filter:
		if team_component_path.is_empty():
			_team = UFrameTeam.of(self)
		else:
			_team = get_node_or_null(team_component_path) as UFrameTeam
	area_entered.connect(_on_area_entered)
	if _health == null:
		push_warning("[UFrameHurtbox2D] 找不到 UFrameHealth：%s" % health_path)

func _on_area_entered(area: Area2D) -> void:
	# 只接受真正的 UFrameHitbox2D，普通 Area2D 不会造成伤害。
	var hitbox := area as UFrameHitbox2D
	if hitbox:
		receive_hit(hitbox)

## 尝试接收一次命中并返回实际伤害。[br]
## 除了 Area2D 的自动进入事件，周期性接触攻击也可以显式调用本方法，
## 从而仍然统一经过 Hitbox、Team、无敌时间和 Health 的完整结算链。
func receive_hit(hitbox: UFrameHitbox2D) -> int:
	if hitbox == null or _health == null or not hitbox.can_hit(self):
		return 0
	if use_team_filter and _team:
		var source_team := UFrameTeam.of(hitbox.source)
		if source_team and not source_team.is_hostile(_team):
			return 0
	if _health.is_invincible():
		return 0
	var applied_damage := _health.take_damage(hitbox.damage, hitbox.source)
	if applied_damage > 0:
		hitbox.mark_hit(self, applied_damage)
	return applied_damage
