extends Node

## 实体阵营关系组件。
##
## 负责保存阵营 ID、敌对列表和友伤规则，并提供局部关系查询。
## 不主动扫描整棵场景树，也不执行伤害结算；[UFrameHurtbox2D] 只在需要时读取它。
## 打开 [code]examples/arena/arena_player.tscn[/code] 可查看本组件作为实体子节点的组合方式。
class_name UFrameTeam

#region 信号
## 阵营 ID 被设置时发出。 [br][br]
## [param old_id] : 原阵营 ID [br]
## [param new_id] : 新阵营 ID
signal team_changed(old_id: int, new_id: int)
#endregion

#region Inspector 配置
## 当前阵营 ID；相同 ID 默认视为友方。
@export var team_id: int = 0

## 显式敌对阵营列表；为空时表示除自身阵营外全部敌对。
@export var hostile_teams: Array[int] = []

## 是否把同阵营目标视为敌对，从而允许友伤。
@export var friendly_fire: bool = false
#endregion

#region 阵营操作
## 把阵营设为 [param new_id]；即使 ID 未变化也会发出 [signal team_changed]。 [br][br]
## [param new_id] : 新阵营 ID
func set_team(new_id: int) -> void:
	var old := team_id
	team_id = new_id
	team_changed.emit(old, new_id)
#endregion

#region 关系查询
## 判断 [param other] 是否敌对；目标为空时视为敌对。 [br][br]
## [param other] : 要比较的阵营组件
func is_hostile(other: UFrameTeam) -> bool:
	if other == null:
		return true  # 无阵营时保持伤害系统独立可用
	if team_id == other.team_id:
		return friendly_fire  # 同阵营关系由友伤开关决定
	if hostile_teams.is_empty():
		return true
	return other.team_id in hostile_teams

## 判断 [param other] 是否为友方。 [br][br]
## [param other] : 要比较的阵营组件
func is_ally(other: UFrameTeam) -> bool:
	return not is_hostile(other)

## 在 [param node] 或其父节点下查找名为 [code]TeamComponent[/code] 的 [UFrameTeam]。 [br]
## 找不到时返回 [code]null[/code]；本方法不会继续向更高层遍历。 [br][br]
## [param node] : 待查找阵营的节点
static func of(node: Node) -> UFrameTeam:
	if not is_instance_valid(node):
		return null
	var team := node.get_node_or_null(^"TeamComponent") as UFrameTeam
	if team:
		return team
	var parent := node.get_parent()
	return parent.get_node_or_null(^"TeamComponent") as UFrameTeam if parent else null
#endregion
