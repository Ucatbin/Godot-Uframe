extends Node

## 通用场景对象池组件
##
## 挂到一个 [Node] 并配置 [member pool_scene]，适合子弹、伤害数字和粒子等高频对象[br]
## 池化场景的根节点与后代应保留默认的 [constant Node.PROCESS_MODE_INHERIT][br]
## 碰撞对象应保留默认的 [code]DISABLE_MODE_REMOVE[/code]，闲置时 Godot 会自动将其移出物理模拟[br]
## 场景含有画面内容时，根节点应继承 [CanvasItem] 或 [Node3D]，以便一次隐藏整棵可视分支[br]
## 可实现 [code]_on_pool_acquire()[/code] 与 [code]_on_pool_release()[/code] 重置自定义状态[br][br]
## [code]示例：[/code]
## [codeblock]
## var bullet := $BulletPool.acquire()
## if bullet:
##     bullet.global_position = muzzle.global_position
##
## $BulletPool.release(bullet)
## [/codeblock]
class_name UFramePool

#region 信号
## [b]实例取出完成[/b][br][br]
## [param instance] : 取出的实例
signal instance_acquired(instance: Node)

## [b]实例归还完成[/b][br][br]
## [param instance] : 归还的实例
signal instance_released(instance: Node)

## [b]实例创建完成[/b][br]
## 预热阶段创建的实例也会触发[br][br]
## [param instance] : 新创建的实例
signal instance_created(instance: Node)
#endregion

#region 配置
## [b]池化场景[/b][br]
## 必须设置
@export var pool_scene: PackedScene

## [b]预热数量[/b][br]
## [code]0[/code] 表示不预创建
@export_range(0, 100000) var initial_size := 0

## [b]最大实例数[/b][br]
## [code]0[/code] 表示没有上限；达到正数上限时会自动复用最早启用的实例
@export_range(0, 100000) var maximum_size := 0
#endregion

#region 运行时状态
## [b]空闲实例[/b]
var _available: Array[Node] = []

## [b]活跃实例[/b][br][br]
## [color=cyan]有序集合：[/color]实例 → 占位值；字典插入顺序就是实例启用顺序。
var _active: Dictionary = {}

## [b]本池实例[/b][br][br]
## [color=cyan]集合：[/color]本池创建且尚未退出场景树的全部实例。
var _owned: Dictionary = {}
#endregion

#region 生命周期
func _ready() -> void:
	if pool_scene == null:
		push_error("[UFramePool] 必须设置 pool_scene")
		return
	var prewarm_count := initial_size if maximum_size == 0 else mini(initial_size, maximum_size)
	for _index in prewarm_count:
		var instance := _create_instance()
		if instance:
			_available.append(instance)
#endregion

#region 主要方法
## [b]获取池化实例[/b][br]
## 达到 [member maximum_size] 且没有空闲对象时，结束最早活跃实例的生命周期并立即复用
func acquire() -> Node:
	if pool_scene == null:
		return null
	var instance: Node = null
	# 正常热路径只从数组末尾 O(1) 取出，不再先扫描整个池。
	while not _available.is_empty() and instance == null:
		var candidate: Variant = _available.pop_back()
		if is_instance_valid(candidate) and not (candidate as Node).is_queued_for_deletion():
			instance = candidate as Node
		else:
			_owned.erase(candidate)
			_active.erase(candidate)
	if not is_instance_valid(instance):
		if maximum_size == 0 or _owned.size() < maximum_size:
			instance = _create_instance()
		else:
			# 只有真正触顶时才进行一次失效清理，避免 HUD 高频 acquire/release
			# 场景在每次获取前都 O(n) 扫描整个池。
			_prune_invalid_instances()
			if _owned.size() < maximum_size:
				instance = _create_instance()
			else:
				instance = _take_oldest_active()
				if is_instance_valid(instance):
					var reusable := _deactivate_instance(instance, false)
					if not reusable:
						# 生命周期钩子若主动销毁了旧实例，容量已经空出，直接补建一个。
						instance = _create_instance() if _owned.size() < maximum_size else null
	if not is_instance_valid(instance) or instance.is_queued_for_deletion():
		return null
	# Dictionary 保持插入顺序；复用实例重新插入后自然成为最新一项。
	_active[instance] = true
	_set_instance_active(instance, true)
	if instance.has_method("_on_pool_acquire"):
		instance.call("_on_pool_acquire")
	instance_acquired.emit(instance)
	return instance

## [b]归还池化实例[/b][br]
## 成功返回 [code]true[/code]；重复归还或归还非本池对象返回 [code]false[/code][br][br]
## [param instance] : 需要归还的实例
func release(instance: Node) -> bool:
	if not is_instance_valid(instance) or instance.is_queued_for_deletion() or not _owned.has(instance) or not _active.erase(instance):
		return false
	_deactivate_instance(instance, true)
	return true

## [b]释放全部实例[/b][br]
## 通常只在销毁池或切换系统时调用
func clear() -> void:
	for instance: Node in _owned:
		if is_instance_valid(instance):
			instance.queue_free()
	_available.clear()
	_active.clear()
	_owned.clear()

## [b]获取池化实例兼容别名[/b][br]
## 新代码应直接使用 [method acquire]
func get_instance() -> Node:
	return acquire()
#endregion

#region 查询方法
## [b]获取活跃实例数[/b][br]
## 退出场景树时会自动维护集合，因此查询成本固定
func get_active_count() -> int:
	return _active.size()

## [b]获取实例总数[/b][br]
## 排队释放的实例会在退出场景树时自动移除
func get_total_count() -> int:
	return _owned.size()
#endregion

#region 内部方法
## [b]取出最早活跃实例[/b][br]
## Dictionary 保持插入顺序，因此第一项就是最早启用的实例
func _take_oldest_active() -> Node:
	var oldest_value: Variant = null
	for candidate_value: Variant in _active:
		oldest_value = candidate_value
		break
	if oldest_value == null:
		return null
	_active.erase(oldest_value)
	return oldest_value as Node

## [b]停用池化实例[/b][br]
## [param cache_instance] 为 [code]false[/code] 时，实例会在同一次获取中立即重新启用[br][br]
## [param instance] : 需要停用的实例[br]
## [param cache_instance] : 是否加入空闲数组
func _deactivate_instance(instance: Node, cache_instance: bool) -> bool:
	if instance.has_method("_on_pool_release"):
		instance.call("_on_pool_release")
	if not is_instance_valid(instance) or instance.is_queued_for_deletion():
		_owned.erase(instance)
		return false
	_set_instance_active(instance, false)
	if cache_instance:
		_available.append(instance)
	instance_released.emit(instance)
	return true

## [b]创建池化实例[/b][br]
## 新实例会作为池节点的子节点加入场景树并立即停用
func _create_instance() -> Node:
	var instance := pool_scene.instantiate()
	if instance == null:
		return null
	add_child(instance)
	_owned[instance] = true
	instance.tree_exiting.connect(_on_instance_exiting.bind(instance), CONNECT_ONE_SHOT)
	_set_instance_active(instance, false)
	instance_created.emit(instance)
	return instance

## [b]设置实例活动状态[/b][br]
## Godot 会根据继承的处理模式和碰撞对象的 [code]disable_mode[/code] 自动退出或恢复物理模拟[br]
## 此处只需切换场景根节点的处理与可见性，不遍历场景结构[br][br]
## [param instance] : 需要设置的实例[br]
## [param active] : 是否启用实例
func _set_instance_active(instance: Node, active: bool) -> void:
	instance.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if instance is CanvasItem:
		(instance as CanvasItem).visible = active
	elif instance is Node3D:
		(instance as Node3D).visible = active

## [b]清理失效实例引用[/b][br]
## 只在池达到容量上限时执行完整扫描
func _prune_invalid_instances() -> void:
	for index in range(_available.size() - 1, -1, -1):
		var instance: Variant = _available[index]
		if not is_instance_valid(instance) or instance.is_queued_for_deletion():
			_available.remove_at(index)
	for instance: Variant in _owned.keys():
		if not is_instance_valid(instance) or instance.is_queued_for_deletion():
			_owned.erase(instance)
			_active.erase(instance)

## [b]处理实例退出场景树[/b][br]
## 从全部运行时集合移除引用[br][br]
## [param instance] : 即将退出的实例
func _on_instance_exiting(instance: Node) -> void:
	_available.erase(instance)
	_active.erase(instance)
	_owned.erase(instance)
#endregion
