extends Node

'''
描述：
	全局事件总线（Autoload 单例）
用法：
	# 发送事件
	EventBus.send("PlayerDamaged", {"damage": 10, "source": self})
	# 订阅事件
	EventBus.subscribe("PlayerDamaged", _on_player_damaged, false, self)
'''

#region 变量
## [b]订阅者列表[/b][br]
## [br]映射 : [param event_name] → [param handlers]
var _subscribers: Dictionary = {}
#endregion

#region 发送/订阅/取消订阅
## [b]发送一个全局事件，所有该事件的订阅者触发一次回调[/b][br][br]
## [param event_name] : 事件标识符，建议大驼峰，如 "PlayerDied"[br]
## [param data] : 附带数据，任意类型，通常是 [Dictionary][br]
## [br]示例：[br]
## [code]EventBus.send("PlayerDied", {"killer": goblin})[/code]
func send(event_name: String, data: Variant = null) -> void:
	if not _subscribers.has(event_name):
		return

	var to_remove: Array = []
	var handlers = _subscribers[event_name]

	for entry in handlers:
		var callable = entry.callable
		var is_once = entry.get("once")
		var target = entry.get("target")

		# 检查失效节点
		if target != null and not is_instance_valid(target):
			to_remove.append(entry)
			continue

		# 调用回调（带 data 参数）
		if callable.get_argument_count() > 0:
			callable.call(data)
		else:
			callable.call()
		
		# 检查一次性订阅
		if is_once:
			to_remove.append(entry)

	# 清理无效/一次性订阅
	for entry in to_remove:
		handlers.erase(entry)

	if handlers.is_empty():
		_subscribers.erase(event_name)

## [b]订阅事件[/b][br][br]
## [param event_name] : 事件名[br]
## [param callable] : 回调函数，签名 : [code]func my_func(data: Variant)[/code][br]
## [param is_once] : 是否为一次性订阅[br]
## [param target] : 绑定到此节点生命周期，如为null则无法自动注销
func subscribe(event_name: String, callable: Callable, is_once: bool = false , target: Object = null) -> void:
	if not _subscribers.has(event_name):
		_subscribers[event_name] = []

	var entry = {
		"callable": callable,
		"once": is_once,
		"target": target
	}
	_subscribers[event_name].append(entry)

	# 绑定自动注销
	if target != null and target is Node:
		if not target.tree_exiting.is_connected(unsubscribe.bind(event_name, callable)):
			target.tree_exiting.connect(
				unsubscribe.bind(event_name, callable),
				CONNECT_ONE_SHOT
			)

## [b]取消订阅[/b][br][br]
## [param event_name] : 事件名[br]
## [param callable] : 回调函数，签名 func my_func(data: Variant)
func unsubscribe(event_name: String, callable: Callable) -> void:
	if not _subscribers.has(event_name):
		return

	var handlers = _subscribers[event_name]
	for i in range(handlers.size() - 1, -1, -1):
		if handlers[i].callable == callable:
			handlers.remove_at(i)

	if handlers.is_empty():
		_subscribers.erase(event_name)
#endregion

#region 辅助方法
## [color=cyan]返回 : [/color]查看当前所有事件和订阅数
func _debug_get_status() -> Dictionary:
	var result := {}
	for key in _subscribers:
		result[key] = _subscribers[key].size()
	return result
#endregion
