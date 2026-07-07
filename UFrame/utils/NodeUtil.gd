class_name NodeUtil

# NodeUtil.gd
# 节点查找安全工具，静态方法，直接 NodeUtil.xxx() 调用
# 避免 get_node_or_null 路径写错直接崩，或节点已释放还访问

# ==========
## 安全查找
# ==========

## 安全获取节点，找不到返回 null 不报错
static func get_node_safe(node: Node, path: NodePath) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	var result := node.get_node_or_null(path)
	return result


## 按 Group 查找，返回第一个（比 get_nodes_in_group[0] 安全）
static func find_in_group(node: Node, group_name: String) -> Node:
	if node == null:
		return null
	var arr := node.get_tree().get_nodes_in_group(group_name)
	if arr.is_empty():
		return null
	return arr[0]


## 按 Group 查找全部，返回 Array（已从场景树移除的节点会自动过滤）
static func find_all_in_group(node: Node, group_name: String) -> Array:
	if node == null:
		return []
	var result: Array = []
	for n in node.get_tree().get_nodes_in_group(group_name):
		if is_instance_valid(n):
			result.append(n)
	return result


# ==========
## 节点操作
# ==========

## 安全移除子节点（先 queue_free 再 remove_child，防止内存泄漏）
static func remove_child_safe(parent: Node, child: Node) -> void:
	if parent == null or child == null:
		return
	if child.is_inside_tree():
		parent.remove_child(child)
	child.queue_free()


## 递归查找子节点（按名称，深度优先）
static func find_child_by_name(node: Node, name_: String) -> Node:
	if node == null:
		return null
	if node.name == name_:
		return node
	for child in node.get_children():
		var result = find_child_by_name(child, name_)
		if result != null:
			return result
	return null


## 获取节点的所有祖先节点路径（用于调试）
static func get_node_path_string(node: Node) -> String:
	if node == null:
		return ""
	var parts: Array[String] = []
	var n := node
	while n != null:
		parts.push_front(n.name)
		n = n.get_parent()
	return "/".join(parts)


# ==========
## 场景树
# ==========

## 判断节点是否还在场景树中（防止已 queue_free 还操作）
static func is_in_tree(node: Node) -> bool:
	if node == null:
		return false
	return node.is_inside_tree()


## 获取 MainLoop 的根节点（等价于 get_tree().root）
static func get_root() -> Window:
	var main_loop = Engine.get_main_loop()
	if main_loop and main_loop.has_method("get_root"):
		return main_loop.get_root()
	return null
