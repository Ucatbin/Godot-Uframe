extends Node

## 可组合行为管理组件
##
## 将多个 [UFrameBehavior] 作为直属子节点，并把管理器与所属实体引用注入行为[br]
## 管理器本身不参与逐帧更新，每个启用的行为使用自己的 Godot 回调
class_name UFrameBehaviorManager

#region 生命周期
func _enter_tree() -> void:
	if not child_entered_tree.is_connected(_on_child_entered_tree):
		child_entered_tree.connect(_on_child_entered_tree)
	for child in get_children():
		if child is UFrameBehavior:
			_bind_behavior(child)
#endregion

#region 主要方法
## [b]设置指定行为[/b][br]
## 成功返回 [code]true[/code]，名称不存在时返回 [code]false[/code][br][br]
## [param behavior_name] : 行为节点名[br]
## [param value] : 是否启用行为
func set_behavior_enabled(behavior_name: StringName, value: bool) -> bool:
	var behavior := get_behavior(behavior_name)
	if behavior == null:
		push_warning("[UFrameBehaviorManager] 找不到行为：%s" % behavior_name)
		return false
	behavior.enabled = value
	return true

## [b]设置全部行为[/b][br][br]
## [param value] : 是否启用全部直属行为
func set_all_enabled(value: bool) -> void:
	for child in get_children():
		if child is UFrameBehavior:
			child.enabled = value
#endregion

#region 查询方法
## [b]按名称获取行为[/b][br]
## 找不到或直属子节点不是 [UFrameBehavior] 时返回 [code]null[/code][br][br]
## [param behavior_name] : 行为节点名
func get_behavior(behavior_name: StringName) -> UFrameBehavior:
	for child in get_children():
		if child.name == behavior_name and child is UFrameBehavior:
			return child
	return null

## [b]判断行为是否存在[/b][br][br]
## [param behavior_name] : 行为节点名
func has_behavior(behavior_name: StringName) -> bool:
	return get_behavior(behavior_name) != null
#endregion

#region 内部方法
## [b]处理直属子节点进入[/b][br]
## 非行为节点会发出警告[br][br]
## [param child] : 新进入场景树的直属子节点
func _on_child_entered_tree(child: Node) -> void:
	if child is UFrameBehavior:
		_bind_behavior(child)
	else:
		push_warning("[UFrameBehaviorManager] 直属子节点 %s 不是 UFrameBehavior" % child.name)

## [b]注入行为引用[/b][br]
## 仅处理当前管理器的直属子节点[br][br]
## [param child] : 需要绑定的行为
func _bind_behavior(child: UFrameBehavior) -> void:
	if child.get_parent() != self:
		return
	child._bind_to_manager(self, get_parent())
#endregion
