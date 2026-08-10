class_name UFramePool
extends Node

## 通用场景对象池组件
##
## 挂到一个 [Node] 并配置 [member pool_scene]，适合子弹、伤害数字和粒子等高频对象[br][br]
## [code]示例：[/code]
## [codeblock]
## var bullet := $BulletPool.acquire()
## if bullet:
##     bullet.global_position = muzzle.global_position
##
## $BulletPool.release(bullet)
## [/codeblock]

#region 信号
## 实例取出完成[br][br]
## [param instance] : 取出的实例
signal instance_acquired(instance: Node)

## 实例归还完成[br]
## 信号触发时实例已经停用；容量溢出复用时，随后会立即进入新的取出生命周期[br][br]
## [param instance] : 归还的实例
signal instance_released(instance: Node)

## 实例创建完成[br]
## 预热阶段创建的实例也会触发[br][br]
## [param instance] : 新创建的实例
signal instance_created(instance: Node)
#endregion

#region 配置
## 池化场景
@export var pool_scene: PackedScene

## 预加载数量[br]
## [code]0[/code] 表示不预创建
@export_range(0, 100000) var initial_size := 0

## 最大实例数[br]
## [code]0[/code] 表示没有上限；达到正数上限时会自动复用最早启用的实例
@export_range(0, 100000) var maximum_size := 0
#endregion

#region 运行时状态
## 空闲实例
var _available: Array[Node] = []

## 活跃实例[br][br]
## 实例 -> 占位值
var _active: Dictionary = {}

## 本池实例[br]
## 本池创建且尚未退出场景树的全部实例
var _owned: Dictionary = {}
#endregion

#region 生命周期
func _ready() -> void:
	if pool_scene == null:
		push_error("[UFramePool] 必须设置 pool_scene")
		return
	# 判断是否预加载数量超过最大数量限制
	var prewarm_count := initial_size if maximum_size == 0 else mini(initial_size, maximum_size)
	for _index in prewarm_count:
		var instance := _create_instance()
		if instance:
			_available.append(instance)
#endregion

#region 主要方法
## 获取池化实例[br]
## 达到 [member maximum_size] 且没有空闲对象时，结束最早活跃实例的生命周期并立即复用
func acquire() -> Node:
	if pool_scene == null:
		return null
	var instance: Node = null
	# 检索空闲实例有效性，从后往前取出第一个有效空闲实例
	while not _available.is_empty() and instance == null:
		var candidate: Variant = _available.pop_back()
		if is_instance_valid(candidate) and not (candidate as Node).is_queued_for_deletion():
			instance = candidate as Node
		else:
			_owned.erase(candidate)
			_active.erase(candidate)
	if not is_instance_valid(instance):
		# 未设上限或未达到 maximum_size 且没有空闲对象时，创建新的对象实例并取出
		if maximum_size == 0 or _owned.size() < maximum_size:
			instance = _create_instance()
		else:
			# 触顶时进行一次失效清理
			_prune_invalid_instances()
			# 清理完毕后本池实例有空缺，则创建新的实例补充
			if _owned.size() < maximum_size:
				instance = _create_instance()
			else:
				instance = _take_oldest_active()
				if is_instance_valid(instance):
					# 溢出复用只结束旧生命周期，不加入空闲数组
					if _end_instance_lifecycle(instance):
						instance_released.emit(instance)
					else:
						# 钩子主动销毁了旧实例，容量已经空出，建新的实例补充
						instance = _create_instance() if _owned.size() < maximum_size else null
	if not is_instance_valid(instance) or instance.is_queued_for_deletion():
		return null
	_active[instance] = true
	_set_instance_active(instance, true)
	if instance.has_method("_on_pool_acquire"):
		instance.call("_on_pool_acquire")
	instance_acquired.emit(instance)
	return instance

## 归还池化实例[br]
## 成功返回 [code]true[/code]；重复归还或归还非本池对象返回 [code]false[/code][br][br]
## [param instance] : 需要归还的实例
func release(instance: Node) -> bool:
	if not is_instance_valid(instance) or instance.is_queued_for_deletion() or not _owned.has(instance) or not _active.erase(instance):
		return false
	if not _end_instance_lifecycle(instance):
		return true
	_available.append(instance)
	instance_released.emit(instance)
	return true

## 释放全部实例[br]
## 通常只在销毁池或切换系统时调用
func clear() -> void:
	for instance: Node in _owned:
		if is_instance_valid(instance):
			instance.queue_free()
	_available.clear()
	_active.clear()
	_owned.clear()
#endregion

#region 查询方法
## 获取活跃实例数
func get_active_count() -> int:
	return _active.size()

## 获取实例总数
func get_total_count() -> int:
	return _owned.size()
#endregion

#region 内部方法
## 取出最早活跃实例
func _take_oldest_active() -> Node:
	var oldest_value: Variant = null
	# Dictionary 保持插入顺序，因此第一项就是最早启用的实例
	for candidate_value: Variant in _active:
		oldest_value = candidate_value
		break
	if oldest_value == null:
		return null
	_active.erase(oldest_value)
	return oldest_value as Node

## 结束当前取出生命周期并停用实例[br][br]
## [param instance] : 需要结束生命周期的实例
func _end_instance_lifecycle(instance: Node) -> bool:
	if instance.has_method("_on_pool_release"):
		instance.call("_on_pool_release")
	if not is_instance_valid(instance) or instance.is_queued_for_deletion():
		_owned.erase(instance)
		return false
	_set_instance_active(instance, false)
	return true

## 创建池化实例；新实例会作为池节点的子节点加入场景树并立即停用[br]
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

## 设置实例活动状态[br]
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

## 清理失效实例引用，只在池达到容量上限时执行完整扫描
func _prune_invalid_instances() -> void:
	for index in range(_available.size() - 1, -1, -1):
		var instance: Variant = _available[index]
		if not is_instance_valid(instance) or instance.is_queued_for_deletion():
			_available.remove_at(index)
	for instance: Variant in _owned.keys():
		if not is_instance_valid(instance) or instance.is_queued_for_deletion():
			_owned.erase(instance)
			_active.erase(instance)

## 处理实例退出场景树[br]
## [param instance] : 即将退出的实例
func _on_instance_exiting(instance: Node) -> void:
	_available.erase(instance)
	_active.erase(instance)
	_owned.erase(instance)
#endregion
