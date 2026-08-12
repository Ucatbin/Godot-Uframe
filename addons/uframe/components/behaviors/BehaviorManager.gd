extends Node

## 可组合行为管理组件。
##
## 负责绑定直属 [UFrameBehavior]、注入所属实体，并提供按节点名查询和统一启停入口。
## 不负责逐帧更新或行为互斥；每个 Behavior 使用自身回调，互斥逻辑交给 [UFrameStateMachine]。
## 打开 [code]examples/arena/arena_player.tscn[/code] 可查看 Manager 与 Behavior 的场景树组合。
class_name UFrameBehaviorManager

#region 生命周期
func _enter_tree() -> void:
	if not child_entered_tree.is_connected(_on_child_entered_tree):
		child_entered_tree.connect(_on_child_entered_tree)
	for child in get_children():
		if child is UFrameBehavior:
			_bind_behavior(child)
#endregion

#region 行为控制
## 设置指定行为是否启用。
## [param behavior_name] 是行为节点名，[param value] 是新的启用状态；找不到时返回 [code]false[/code]。
func set_behavior_enabled(behavior_name: StringName, value: bool) -> bool:
	var behavior := get_behavior(behavior_name)
	if behavior == null:
		push_warning("[UFrameBehaviorManager] 找不到行为：%s" % behavior_name)
		return false
	behavior.enabled = value
	return true

## 设置全部直属行为是否启用。[param value] 是统一写入的启用状态。
func set_all_enabled(value: bool) -> void:
	for child in get_children():
		if child is UFrameBehavior:
			child.enabled = value
#endregion

#region 行为查询
## 按节点名获取直属行为；找不到或节点类型不符时返回 [code]null[/code]。
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
## 处理直属子节点进入；[param child] 不是 [UFrameBehavior] 时发出警告。
func _on_child_entered_tree(child: Node) -> void:
	if child is UFrameBehavior:
		_bind_behavior(child)
	else:
		push_warning("[UFrameBehaviorManager] 直属子节点 %s 不是 UFrameBehavior" % child.name)

## 向直属 [param child] 注入当前管理器及其所属实体。
func _bind_behavior(child: UFrameBehavior) -> void:
	if child.get_parent() != self:
		return
	child._bind_to_manager(self, get_parent())
#endregion
