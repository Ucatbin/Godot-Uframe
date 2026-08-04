extends Node

## 实体阵营关系组件
##
## 挂到玩家、敌人等实体的子节点，并配置 [member team_id][br]
## 使用 [method of] 查找目标阵营，再通过 [method is_hostile] 或 [method is_ally] 判断关系
class_name UFrameTeam

#region 信号
## [b]阵营变更[/b][br][br]
## [param old_id] : 原阵营 ID[br]
## [param new_id] : 新阵营 ID
signal team_changed(old_id: int, new_id: int)
#endregion

#region 配置
## [b]阵营 ID[/b][br]
## 相同 ID 默认视为友方
@export var team_id: int = 0

## [b]敌对阵营列表[/b][br]
## 为空时表示除自身阵营外全部敌对
@export var hostile_teams: Array[int] = []

## [b]是否允许友伤[/b]
@export var friendly_fire: bool = false
#endregion

#region 主要方法
## [b]设置阵营[/b][br]
## 即使 ID 没有变化也会发出 [signal team_changed][br][br]
## [param new_id] : 新阵营 ID
func set_team(new_id: int) -> void:
	var old = team_id
	team_id = new_id
	team_changed.emit(old, new_id)
#endregion

#region 查询方法
## [b]判断是否敌对[/b][br]
## 目标为空时视为敌对[br][br]
## [param other] : 目标阵营组件
func is_hostile(other: UFrameTeam) -> bool:
	if other == null:
		return true  # 无阵营视为敌方
	if team_id == other.team_id:
		return friendly_fire  # 同阵营看友伤开关
	if hostile_teams.is_empty():
		return true
	return other.team_id in hostile_teams

## [b]判断是否友方[/b][br][br]
## [param other] : 目标阵营组件
func is_ally(other: UFrameTeam) -> bool:
	return not is_hostile(other)

## [b]查找阵营组件[/b][br]
## 查找目标节点或其父节点上名为 [code]TeamComponent[/code] 的 [UFrameTeam][br][br]
## [param node] : 目标节点
static func of(node: Node) -> UFrameTeam:
	if node == null:
		return null
	if node.has_node("TeamComponent"):
		return node.get_node("TeamComponent")
	if node.get_parent() and node.get_parent().has_node("TeamComponent"):
		return node.get_parent().get_node("TeamComponent")
	return null
#endregion
