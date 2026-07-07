extends Node

'''
全局事件总线（Autoload 单例）

用法：
	# 发送事件
	EventBus.send("PlayerDamaged", {"damage": 10, "source": self})
	# 订阅事件
	EventBus.subscribe("PlayerDamaged", _on_player_damaged, self)
	# 一次性监听
	EventBus.once("WaveComplete", _on_wave_complete, self)
'''

#region 变量
## [b]订阅注册表[/b][br]
## [br]映射：[br]
## [param event_name] → [param handlers]
var _subscribers: Dictionary = {}

## [b]待清理的目标[/b][br]
## 用于延迟清理
var _pending_cleanup: Array = []
#endregion

#region 发送/订阅/取消订阅
## [b]发送一个全局事件[/b][br]
## 所有该事件的订阅者触发一次回调[br]
## [br]示例：[br]
## [code]EventBus.send("PlayerDied", {"killer": goblin})[/code][br]
## [br]参数：[br]
## [param event_name] : 事件标识符，建议大驼峰，如 [code]"PlayerDied"[/code][br]
## [param data] : 附带数据，任意类型，通常是 [Dictionary]
func send(event_name: String, data: Variant = null) -> void:
	if not _subscribers.has(event_name):
		return

	var handlers = _subscribers[event_name]
	var to_remove: Array = []

	for entry in handlers:
		var callable: Callable = entry.callable
		var target = entry.get("target")
		var is_once: bool = entry.get("once", false)

		# 目标节点已无效，标记删除
		if target != null and not is_instance_valid(target):
			to_remove.append(entry)
			continue

		# 调用回调（带 data 参数）
		if callable.get_argument_count() > 0:
			callable.call(data)
		else:
			callable.call()

		if once:
			to_remove.append(entry)

	# 清理无效/一次性监听
	for entry in to_remove:
		handlers.erase(entry)

	if handlers.is_empty():
		_subscribers.erase(event_name)

## [b]订阅事件[/b][br]
## 当 target 退出场景树时，订阅自动注销，无需手动调用 unsubscribe[br]
## [br]参数：[br]
## [param event_name] : 事件名[br]
## [param callable] : 回调函数，签名 [code]func my_func(data: Variant)[/code][br]
## [param target] : 可选，绑定到此节点生命周期
func subscribe(event_name: String, callable: Callable, target: Object = null) -> void:
	if not _subscribers.has(event_name):
		_subscribers[event_name] = []

	var entry = {
		"callable": callable,
		"target": target,
		"once": false
	}
	_subscribers[event_name].append(entry)

	# 绑定自动注销
	if target != null and target is Node:
		if not target.tree_exiting.is_connected(_on_target_exiting.bind(event_name, callable, target)):
			target.tree_exiting.connect(
				_on_target_exiting.bind(event_name, callable, target).unbind(1),
				CONNECT_ONE_SHOT
			)

## [b]单次订阅事件[/b][br]
## 触发后自动注销[br]
## [br]参数：[br]
## [param event_name] : 事件名[br]
## [param callable] : 回调函数，签名 func my_func(data: Variant)[br]
## [param target] : 可选，绑定到此节点生命周期
func once(event_name: String, callable: Callable, target: Object = null) -> void:
	if not _subscribers.has(event_name):
		_subscribers[event_name] = []

	var entry = {
		"callable": callable,
		"target": target,
		"once": true
	}
	_subscribers[event_name].append(entry)

	if target != null and target is Node:
		if not target.tree_exiting.is_connected(_on_target_exiting.bind(event_name, callable, target)):
			target.tree_exiting.connect(
				_on_target_exiting.bind(event_name, callable, target).unbind(1),
				CONNECT_ONE_SHOT
			)
	
## [b]取消订阅[/b][br]
## 通常不需要主动调用[br]
## [br]参数：[br]
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
## [b]自动注销[/b]
func _on_target_exiting(event_name: String, callable: Callable, _target: Object) -> void:
	unsubscribe(event_name, callable)

## [b][color=cyan]调试[/color][/b]：[br]
## 查看当前所有事件和订阅数
func _debug_get_status() -> Dictionary:
	var result := {}
	for key in _subscribers:
		result[key] = _subscribers[key].size()
	return result
#endregion
