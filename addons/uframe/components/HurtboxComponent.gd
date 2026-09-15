extends Area2D

## 受击判定框组件。
##
## 负责接收 [UFrameHitbox2D]、执行可选阵营过滤，并把伤害交给 [UFrameHealth] 结算。
## 不保存生命值或伤害表现；默认依赖同级位置名为 [code]HealthComponent[/code] 的生命组件。
## 打开 [code]examples/arena/arena_player.tscn[/code] 可查看以下场景组合：
## [codeblock]
## Player
## ├── HealthComponent       # UFrameHealth
## └── HurtboxComponent      # UFrameHurtbox2D
##     └── CollisionShape2D
## [/codeblock]
class_name UFrameHurtbox2D

#region Inspector 配置
## 需要接收伤害的 [UFrameHealth] 节点路径。
@export var health_path: NodePath = ^"../HealthComponent"

## 是否过滤友军伤害；仅在双方都有 [UFrameTeam] 时生效。
@export var use_team_filter := true

## 可选的 [UFrameTeam] 节点路径；留空时按 [code]TeamComponent[/code] 命名约定查找。
@export var team_component_path: NodePath = ^"../TeamComponent"
#endregion

#region 依赖引用
## 由 [member health_path] 解析的生命组件。
var _health: UFrameHealth

## 由 [member team_component_path] 或命名约定解析的可选阵营组件。
## 不存在时不会产生警告，也不会阻止伤害。
var _team: UFrameTeam
#endregion

#region 生命周期
## 解析局部依赖并连接 [signal Area2D.area_entered]。
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

#region 伤害结算
## 接收 [param hitbox] 并执行完整伤害结算，返回实际伤害。 [br]
## 周期性接触攻击也可以显式调用本方法，而不必伪造区域进入事件。 [br][br]
## [param hitbox] : 提供攻击信息的 Hitbox
func receive_hit(hitbox: UFrameHitbox2D) -> int:
	if hitbox == null or _health == null or not hitbox.can_hit(self):
		return 0
	if use_team_filter and _team:
		var source_team := UFrameTeam.of(hitbox.source)
		if source_team and not source_team.is_hostile(_team):
			return 0
	var applied_damage := _health.take_damage(hitbox.damage, hitbox.source)
	if applied_damage > 0:
		hitbox.mark_hit(self, applied_damage)
	return applied_damage
#endregion

#region 碰撞输入
## 把进入的 [param area] 识别为 Hitbox；普通 [Area2D] 不会造成伤害。 [br][br]
## [param area] : 进入受击区域的节点
func _on_area_entered(area: Area2D) -> void:
	var hitbox := area as UFrameHitbox2D
	if hitbox:
		receive_hit(hitbox)
#endregion
