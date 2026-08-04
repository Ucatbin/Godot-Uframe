extends Node

## 轻量全局事件总线
##
## 推荐用于低频跨系统通知[br]
## 同一个节点内部或高频战斗逻辑应优先使用 Godot 原生 [code]signal[/code] 或直接调用[br][br]
## [code]示例：[/code]
## [codeblock]
## UFrame.events.subscribe(&"coins_changed", _on_coins_changed)
## UFrame.events.emit_event(&"coins_changed", 10)
## UFrame.events.unsubscribe(&"coins_changed", _on_coins_changed)
## [/codeblock]
class_name UFrameEventBus

#region 运行时状态
## [b]订阅者[/b][br][br]
## [color=cyan]映射： [/color]事件名 → 订阅信息数组。
var _subscribers: Dictionary[StringName, Array] = {}
#endregion

#region 主要方法
## [b]发送事件[/b][br][br]
## [param event_name] 事件标识符[br]
## [param data] 事件传递的数据
func emit_event(event_name: StringName, data: Variant = null) -> void:
	var handlers: Array = _subscribers.get(event_name, [])
	if handlers.is_empty():
		return
	# 使用副本遍历，允许回调执行期间安全地订阅或取消订阅。
	for entry: Dictionary in handlers.duplicate():
		var callback: Callable = entry.callback
		if not callback.is_valid():
			_remove_entry(event_name, entry)
			continue
		# once 必须在回调前移除。否则回调内部再次发送同一事件时会重复进入。
		if entry.once:
			unsubscribe(event_name, callback)
		if callback.get_argument_count() == 0:
			callback.call()
		else:
			callback.call(data)

## 订阅事件。重复订阅同一个 Callable 会被忽略。
## [param once] 为 true 时，回调执行一次后自动移除。
func subscribe(event_name: StringName, callback: Callable, once := false) -> void:
	if not callback.is_valid():
		push_error("[UFrameEventBus] Invalid callback for %s" % event_name)
		return
	var handlers: Array = _subscribers.get_or_add(event_name, [])
	for entry: Dictionary in handlers:
		if entry.callback == callback:
			return
	handlers.append({"callback": callback, "once": once})

## 取消指定回调。即使回调没有订阅，调用也不会报错。
func unsubscribe(event_name: StringName, callback: Callable) -> void:
	var handlers: Array = _subscribers.get(event_name, [])
	for index in range(handlers.size() - 1, -1, -1):
		if handlers[index].callback == callback:
			handlers.remove_at(index)
	if handlers.is_empty():
		_subscribers.erase(event_name)

## 清理订阅。event_name 为空时清理全部事件，否则只清理指定事件。
func clear(event_name: StringName = &"") -> void:
	if event_name.is_empty():
		_subscribers.clear()
	else:
		_subscribers.erase(event_name)
#endregion

#region 内部方法
func _remove_entry(event_name: StringName, entry: Dictionary) -> void:
	var handlers: Array = _subscribers.get(event_name, [])
	handlers.erase(entry)
	if handlers.is_empty():
		_subscribers.erase(event_name)
#endregion
