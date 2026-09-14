extends Node

## 可组合行为管理组件。
##
## 用于简单非互斥逻辑。 [br]
## 负责绑定直属 [UFrameBehavior]、注入所属实体，并提供按节点名查询和统一启停入口。
class_name UFrameBehaviorManager

#region 生命周期
func _enter_tree() -> void:
	# 为行为节点绑定注入
	if not child_entered_tree.is_connected(_on_child_entered_tree):
		child_entered_tree.connect(_on_child_entered_tree)
	for child in get_children():
		if child is UFrameBehavior:
			_bind_behavior(child)
#endregion

#region 行为控制
## 设置指定行为是否启用。 [br][br]
## [param behavior_name] 行为节点名 [br]
## [param value] 新的启用状态
func set_behavior_enabled(behavior_name: StringName, value: bool) -> bool:
	var behavior := get_behavior(behavior_name)
	if behavior == null:
		push_warning("[UFrameBehaviorManager] 找不到行为：%s" % behavior_name)
		return false
	behavior.enabled = value
	return true

## 设置全部直属行为是否启用。 [br][br]
## [param value] 启用状态
func set_all_enabled(value: bool) -> void:
	for child in get_children():
		if child is UFrameBehavior:
			child.enabled = value
#endregion

#region 行为查询
## 按节点名获取直属行为；找不到或节点类型不符时返回 [code]null[/code]。 [br][br]
## [param behavior_name] 节点名
func get_behavior(behavior_name: StringName) -> UFrameBehavior:
	for child in get_children():
		if child.name == behavior_name and child is UFrameBehavior:
			return child
	return null

## 判断是否存在名为 [param behavior_name] 的直属行为。
func has_behavior(behavior_name: StringName) -> bool:
	return get_behavior(behavior_name) != null
#endregion

#region 行为绑定
## 处理直属子节点进入[br][br]
## [param child] 子行为
func _on_child_entered_tree(child: Node) -> void:
	if child is UFrameBehavior:
		_bind_behavior(child)
	else:
		push_warning("[UFrameBehaviorManager] 直属子节点 %s 不是 UFrameBehavior" % child.name)

## 向直属 [param child] 注入当前管理器及其所属实体。
## [param child] : 需要注入的行为节点
func _bind_behavior(child: UFrameBehavior) -> void:
	if child.get_parent() != self:
		return
	child._bind_to_manager(self, get_parent())
#endregion
