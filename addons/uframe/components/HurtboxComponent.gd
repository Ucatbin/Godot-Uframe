extends Area2D

## 受击判定框组件
##
## 作为 Hitbox/Hurtbox 系统的统一伤害结算入口，负责阵营、无敌时间与生命值检查[br]
## 默认查找同级位置名为 [code]HealthComponent[/code] 的 [UFrameHealth][br][br]
## [code]推荐场景结构：[/code]
## [codeblock]
## Player
## ├── HealthComponent       # UFrameHealth
## └── HurtboxComponent      # UFrameHurtbox2D
##     └── CollisionShape2D
## [/codeblock]
class_name UFrameHurtbox2D

#region 配置
## [b]生命组件路径[/b]
@export var health_path: NodePath = ^"../HealthComponent"

## [b]是否过滤友军伤害[/b][br]
## 仅在双方都有 [UFrameTeam] 时生效；任意一方没有阵营组件时仍允许伤害
@export var use_team_filter := true

## [b]阵营组件路径[/b][br]
## 留空时按 [code]TeamComponent[/code] 命名约定查找
@export var team_component_path: NodePath = ^"../TeamComponent"
#endregion

#region 运行时状态
## [b]生命组件缓存[/b]
var _health: UFrameHealth

## [b]阵营组件缓存[/b][br]
## 不存在时不会产生警告，也不会阻止伤害
var _team: UFrameTeam
#endregion

#region 生命周期
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
#endregion

#region 主要方法
## [b]接收命中[/b][br]
## 返回实际伤害；周期性接触攻击也可以显式调用本方法复用完整结算链[br][br]
## [param hitbox] : 进入本受击框的攻击判定框
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
#endregion

#region 内部方法
## [b]处理区域进入[/b][br]
## 普通 [Area2D] 不会造成伤害[br][br]
## [param area] : 进入本受击框的区域
func _on_area_entered(area: Area2D) -> void:
	var hitbox := area as UFrameHitbox2D
	if hitbox:
		receive_hit(hitbox)
#endregion
