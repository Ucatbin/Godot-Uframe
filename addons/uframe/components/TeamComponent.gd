class_name UFrameTeam
extends Node

## 阵营关系组件。挂到玩家、敌人等实体的子 Node 上，在 Inspector 设置 Team ID。
## 使用 [code]UFrameTeam.of(target)[/code] 查找目标阵营，再调用 is_hostile() 判断敌我。

#region 变量
## [b]阵营 ID[/b][br]
## 相同 team_id 为友方，不同则为敌方
@export var team_id: int = 0

## [b]敌对阵营列表[/b][br]
## 为空时表示除自身阵营外全是敌人
@export var hostile_teams: Array[int] = []

## [b]是否允许友伤[/b]
@export var friendly_fire: bool = false
#endregion

#region 信号
## [b]阵营变更[/b]
signal team_changed(old_id: int, new_id: int)
#endregion

#region 公开方法
## [b]判断是否敌对[/b][br]
## [param other]：目标实体的 UFrameTeam
func is_hostile(other: UFrameTeam) -> bool:
	if other == null:
		return true  # 无阵营视为敌方
	if team_id == other.team_id:
		return friendly_fire  # 同阵营看友伤开关
	if hostile_teams.is_empty():
		return true
	return other.team_id in hostile_teams

## [b]判断是否友方[/b]
func is_ally(other: UFrameTeam) -> bool:
	return not is_hostile(other)

## 查找目标节点或其父节点上名为 TeamComponent 的 UFrameTeam。
static func of(node: Node) -> UFrameTeam:
	if node == null:
		return null
	if node.has_node("TeamComponent"):
		return node.get_node("TeamComponent")
	if node.get_parent() and node.get_parent().has_node("TeamComponent"):
		return node.get_parent().get_node("TeamComponent")
	return null

## [b]设置阵营[/b]
func set_team(new_id: int) -> void:
	var old = team_id
	team_id = new_id
	team_changed.emit(old, new_id)
#endregion
