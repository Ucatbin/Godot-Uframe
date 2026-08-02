extends Node

## 行为管理容器
##
## 将多个 UFrameBehavior 子节点放在本节点下[br]
## BehaviorManager 不参与逐帧更新，每个行为仍使用自己的 Godot 回调
class_name UFrameBehaviorManager

func _enter_tree() -> void:
	if not child_entered_tree.is_connected(_on_child_entered_tree):
		child_entered_tree.connect(_on_child_entered_tree)
	for child in get_children():
		if child is UFrameBehavior:
			_bind_behavior(child)

## [b]按直属子节点名称获取行为[/b][br]
## 找不到或目标不是 UFrameBehavior 时返回 null。
func get_behavior(behavior_name: StringName) -> UFrameBehavior:
	for child in get_children():
		if child.name == behavior_name and child is UFrameBehavior:
			return child
	return null

## 是否存在指定名称的直属行为。
func has_behavior(behavior_name: StringName) -> bool:
	return get_behavior(behavior_name) != null

## 启用或禁用指定行为。成功返回 true，名称不存在时返回 false。
func set_behavior_enabled(behavior_name: StringName, value: bool) -> bool:
	var behavior := get_behavior(behavior_name)
	if behavior == null:
		push_warning("[UFrameBehaviorManager] 找不到行为：%s" % behavior_name)
		return false
	behavior.enabled = value
	return true

## 一次启用或禁用全部直属行为。
func set_all_enabled(value: bool) -> void:
	for child in get_children():
		if child is UFrameBehavior:
			child.enabled = value

func _on_child_entered_tree(child: Node) -> void:
	if child is UFrameBehavior:
		_bind_behavior(child)
	else:
		push_warning("[UFrameBehaviorManager] 直属子节点 %s 不是 UFrameBehavior" % child.name)

func _bind_behavior(child: UFrameBehavior) -> void:
	if child.get_parent() != self:
		return
	child._bind_to_manager(self, get_parent())
