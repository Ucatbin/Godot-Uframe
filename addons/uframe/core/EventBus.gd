extends Node

## 轻量全局事件总线
##
## 推荐用于低频跨系统通知[br]
## 同一个节点内部或高频战斗逻辑应优先使用 Godot 原生 [code]signal[/code] 或直接调用[br][br]
## [code]示例：[/code]
## [codeblock]
## UFrame.events.subscribe(&"coins_changed", _on_coins_changed)
## UFrame.events.publish(&"coins_changed", 10)
## UFrame.events.unsubscribe(&"coins_changed", _on_coins_changed)
## [/codeblock]
class_name UFrameEventBus

#region 运行时状态
## [b]订阅表[/b][br][br]
## [color=cyan]映射：[/color]事件名 → 订阅信息数组，每条信息包含 [code]callback[/code] 和 [code]once[/code]。
var _subscribers: Dictionary[StringName, Array] = {}
#endregion

#region 主要方法
## 发布事件，调用所有回调[br][br]
## [param event_name] : 事件标识符[br]
## [param data] : 事件传递的数据
func publish(event_name: StringName, data: Variant = null) -> void:
	#获取事件的全部订阅信息数组
	var handlers: Array = _subscribers.get(event_name, [])
	if handlers.is_empty():
		return
	#复制事件订阅信息数组快照
	for entry: Dictionary in handlers.duplicate():
		var callback: Callable = entry.callback
		#清理失效回调
		if not callback.is_valid():
			_remove_entry(event_name, entry)
			continue
		#提前取消单次回调的订阅
		if entry.once:
			unsubscribe(event_name, callback)
		#执行回调
		if callback.get_argument_count() == 0:
			callback.call()
		else:
			callback.call(data)

## 订阅事件回调[br]
## 重复订阅同一个 [Callable] 会被忽略[br]
## [param once] 为 [code]true[/code] 时，会在首次执行前自动取消订阅，避免递归发布时重复进入[br][br]
## [param event_name] : 事件标识符[br]
## [param callback] : 事件触发时调用的零参数或单参数回调[br]
## [param once] : 是否只执行一次
func subscribe(event_name: StringName, callback: Callable, once := false) -> void:
	#检查回调是否有效
	if not callback.is_valid():
		push_error("[UFrameEventBus] Invalid callback for %s" % event_name)
		return
	#获取或创建指定事件订阅信息数组
	var handlers: Array = _subscribers.get_or_add(event_name, [])
	#检查重复回调
	for entry: Dictionary in handlers:
		if entry.callback == callback:
			return
	#订阅回调
	handlers.append({"callback": callback, "once": once})

## [b]取消订阅事件回调[/b][br][br]
## [param event_name] : 事件标识符[br]
## [param callback] : 指定的回调
func unsubscribe(event_name: StringName, callback: Callable) -> void:
	#获取指定事件订阅信息数组
	var handlers: Array = _subscribers.get(event_name, [])
	#遍历指定回调并移除
	for index in range(handlers.size() - 1, -1, -1):
		if handlers[index].callback == callback:
			handlers.remove_at(index)
	#清理无回调的事件
	if handlers.is_empty():
		_subscribers.erase(event_name)

## [b]清理订阅[/b][br][br]
## [param event_name] : 事件标识符[br]
## 为空时清理全部事件，否则只清理指定事件；不会执行被移除的回调
func clear(event_name: StringName = &"") -> void:
	if event_name.is_empty():
		_subscribers.clear()
	else:
		_subscribers.erase(event_name)
#endregion

#region 内部方法
## [b]移除指定订阅记录[/b][br]
## 重新取得事件当前的订阅数组，避免回调在发布期间修改订阅关系后误删新记录[br][br]
## [param event_name] : 事件标识符[br]
## [param entry] : 需要移除的订阅信息
func _remove_entry(event_name: StringName, entry: Dictionary) -> void:
	#获取指定事件订阅信息数组
	var handlers: Array = _subscribers.get(event_name, [])
	#移除指定指定事件订阅信息
	handlers.erase(entry)
	#清理无回调的事件
	if handlers.is_empty():
		_subscribers.erase(event_name)
#endregion
