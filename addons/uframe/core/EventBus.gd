extends Node

## 轻量全局事件总线
##
## 负责按事件 ID 发布低频跨系统通知，不负责实体内或逐帧通信。
## 同一局部范围应优先使用 Godot 原生 [code]signal[/code] 或直接调用。
## 运行时通过 [code]UFrame.events[/code] 使用。
##
## 使用示例：
## [codeblock]
## UFrame.events.subscribe(&"coins_changed", _on_coins_changed)
## UFrame.events.publish(&"coins_changed", 10)
## UFrame.events.unsubscribe(&"coins_changed", _on_coins_changed)
## [/codeblock]
class_name UFrameEventBus

#region 运行时状态
## 事件订阅表：事件名 → 包含 [code]callback[/code] 与 [code]once[/code] 的记录数组。
var _subscribers: Dictionary[StringName, Array] = {}
#endregion

#region 主要方法
## 发布事件并调用当前全部有效回调。
## [param event_name] 是事件标识符，[param data] 是可选载荷。
func publish(event_name: StringName, data: Variant = null) -> void:
	# 使用快照，允许回调在发布期间安全修改原订阅表
	var handlers: Array = _subscribers.get(event_name, [])
	if handlers.is_empty():
		return
	for entry: Dictionary in handlers.duplicate():
		var callback: Callable = entry.callback
		if not callback.is_valid():
			_remove_entry(event_name, entry)
			continue
		# 执行前取消 once 订阅，避免回调递归发布时再次进入
		if entry.once:
			unsubscribe(event_name, callback)
		if callback.get_argument_count() == 0:
			callback.call()
		else:
			callback.call(data)

## 订阅零参数或单参数回调；重复订阅同一个 [Callable] 会被忽略。
## [param once] 为 [code]true[/code] 时，在首次执行前自动取消订阅，避免递归发布重复进入。
func subscribe(event_name: StringName, callback: Callable, once: bool = false) -> void:
	if not callback.is_valid():
		push_error("[UFrameEventBus] 事件 %s 的回调无效" % event_name)
		return
	var handlers: Array = _subscribers.get_or_add(event_name, [])
	for entry: Dictionary in handlers:
		if entry.callback == callback:
			return
	handlers.append({"callback": callback, "once": once})

## 取消指定事件的回调；目标不存在时不产生副作用。
func unsubscribe(event_name: StringName, callback: Callable) -> void:
	var handlers: Array = _subscribers.get(event_name, [])
	for index in range(handlers.size() - 1, -1, -1):
		if handlers[index].callback == callback:
			handlers.remove_at(index)
	if handlers.is_empty():
		_subscribers.erase(event_name)

## 清理订阅；[param event_name] 为空时清理全部事件，否则只清理指定事件。
func clear(event_name: StringName = &"") -> void:
	if event_name.is_empty():
		_subscribers.clear()
	else:
		_subscribers.erase(event_name)
#endregion

#region 内部方法
## 从事件当前的订阅数组中移除指定记录。
## 重新取得当前数组，可避免发布期间订阅关系变化后操作旧快照。
func _remove_entry(event_name: StringName, entry: Dictionary) -> void:
	var handlers: Array = _subscribers.get(event_name, [])
	handlers.erase(entry)
	if handlers.is_empty():
		_subscribers.erase(event_name)
#endregion
