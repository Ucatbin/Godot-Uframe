extends Node

## 通用场景对象池组件。
##
## 负责 PackedScene 的预热、取出、归还、容量限制，以及场景根的处理模式和可见性切换。
## 不猜测或重置音频、粒子、Timer、Tween 与业务数据；池化场景根应在生命周期钩子中处理这些内容。
## 打开 [code]examples/arena/arena_demo.tscn[/code] 可查看有限容量 Pool 在关卡场景中的静态配置。
## [codeblock]
## var bullet := $BulletPool.acquire()
## if bullet:
##     bullet.global_position = muzzle.global_position
##
## $BulletPool.release(bullet)
## [/codeblock]
class_name UFramePool

#region 信号
## 实例完成激活和取出钩子后发出。 [br][br]
## [param instance] : 本次操作的池化实例
signal instance_acquired(instance: Node)

## 实例完成归还钩子并停用后发出。 [br]
## 容量溢出复用时，该实例随后会立即进入新的取出生命周期。 [br][br]
## [param instance] : 本次操作的池化实例
signal instance_released(instance: Node)

## 新实例完成入树和停用后发出；预热阶段创建的实例也会触发。 [br][br]
## [param instance] : 本次操作的池化实例
signal instance_created(instance: Node)
#endregion

#region Inspector 配置
## 每次创建时实例化的场景；未设置时 Pool 不可用。
@export var pool_scene: PackedScene

## ready 阶段预创建的实例数量；[code]0[/code] 表示不预热。
@export_range(0, 100000) var initial_size := 0

## 本池拥有的最大实例数。
## [code]0[/code] 表示没有上限；达到正数上限时会结束并复用最早活跃的生命周期。
@export_range(0, 100000) var maximum_size := 0
#endregion

#region 运行时状态
## 当前可直接复用的空闲实例。
var _available: Array[Node] = []

## 当前活跃实例到占位值的有序映射；插入顺序代表本次取出的先后。
var _active: Dictionary = {}

## 本池创建且尚未退出场景树的全部实例集合。
var _owned: Dictionary = {}

## 正在执行一次创建、取出、归还或清空事务时为 true，避免生命周期钩子和信号同步重入。
var _lifecycle_transaction_active := false
#endregion

#region 生命周期
## 首次入树时先锁定生命周期事务，覆盖已有池实例早于 Pool 执行 ready 的阶段。
func _enter_tree() -> void:
	if not is_node_ready():
		_lifecycle_transaction_active = true

## 校验池化场景并按容量限制完成预热。
func _ready() -> void:
	if pool_scene == null:
		push_error("[UFramePool] 必须设置 pool_scene")
		_lifecycle_transaction_active = false
		return
	# acquire() 可能在 Pool 入树前被调用，因此只补足与预热目标的差值
	var target_size := initial_size if maximum_size == 0 else mini(initial_size, maximum_size)
	while _owned.size() < target_size:
		var instance := _create_instance()
		if not is_instance_valid(instance) or instance.is_queued_for_deletion():
			break
		# 创建通知返回后仍未进入活跃生命周期的实例才加入空闲数组
		if not _active.has(instance):
			_available.append(instance)
	_lifecycle_transaction_active = false
#endregion

#region 池生命周期
## 获取一个已经激活的池化实例。 [br]
## 达到 [member maximum_size] 且没有空闲项时，结束最早活跃实例的生命周期并立即复用。 [br]
## [member pool_scene] 未配置或无法获得有效实例时返回 [code]null[/code]。
func acquire() -> Node:
	if pool_scene == null:
		return null
	if _lifecycle_transaction_active:
		push_warning("[UFramePool] 生命周期事务期间不能同步 acquire()；请使用 call_deferred()")
		return null
	_lifecycle_transaction_active = true
	var instance: Node = null
	# 从末尾取出第一个有效空闲实例
	while not _available.is_empty() and instance == null:
		var candidate: Variant = _available.pop_back()
		if (
			is_instance_valid(candidate)
			and not (candidate as Node).is_queued_for_deletion()
			and _owned.has(candidate)
		):
			instance = candidate as Node
		else:
			_owned.erase(candidate)
			_active.erase(candidate)
	if not is_instance_valid(instance):
		# 没有空闲项且容量允许时创建新实例
		if maximum_size == 0 or _owned.size() < maximum_size:
			instance = _create_instance()
		else:
			# 正常溢出路径直接取最早活跃项，不扫描整个对象池
			instance = _take_oldest_active()
			var reuses_active_lifecycle := is_instance_valid(instance)
			if not is_instance_valid(instance):
				if _owned.size() < maximum_size:
					# 惰性清理失效活跃项后，优先补齐已经空出的容量
					instance = _create_instance()
				else:
					# 容量账本显示已满，却没有可用或活跃实例时才执行完整修复
					_repair_bookkeeping()
					instance = _take_oldest_active()
					reuses_active_lifecycle = is_instance_valid(instance)
					if not is_instance_valid(instance) and _owned.size() < maximum_size:
						instance = _create_instance()
			if reuses_active_lifecycle:
				# 溢出复用只结束旧生命周期，不加入空闲数组
				if _end_instance_lifecycle(instance):
					instance_released.emit(instance)
				else:
					# 钩子销毁或移出旧实例后，用空出的容量补建实例
					instance = _create_instance() if _owned.size() < maximum_size else null
	if not is_instance_valid(instance) or instance.is_queued_for_deletion() or not _owned.has(instance):
		_lifecycle_transaction_active = false
		return null
	_active[instance] = true
	_set_instance_active(instance, true)
	if instance.has_method("_on_pool_acquire"):
		instance.call("_on_pool_acquire")
	if not is_instance_valid(instance) or instance.is_queued_for_deletion() or not _owned.has(instance):
		_lifecycle_transaction_active = false
		return null
	instance_acquired.emit(instance)
	_lifecycle_transaction_active = false
	if not is_instance_valid(instance) or instance.is_queued_for_deletion() or not _owned.has(instance):
		return null
	return instance

## 归还 [param instance] 并结束本次取出生命周期。 [br]
## 成功返回 [code]true[/code]；实例无效、正在删除、非本池所有或已经归还时返回 [code]false[/code]。 [br][br]
## [param instance] : 本次操作的池化实例
func release(instance: Node) -> bool:
	if _lifecycle_transaction_active:
		push_warning("[UFramePool] 生命周期事务期间不能同步 release()；请使用 call_deferred()")
		return false
	_lifecycle_transaction_active = true
	if not is_instance_valid(instance) or instance.is_queued_for_deletion() or not _owned.has(instance) or not _active.erase(instance):
		_lifecycle_transaction_active = false
		return false
	if not _end_instance_lifecycle(instance):
		_lifecycle_transaction_active = false
		return true
	_available.append(instance)
	instance_released.emit(instance)
	_lifecycle_transaction_active = false
	return true

## 排队释放本池拥有的全部有效实例，并立即清空内部引用。 [br]
## 通常只在销毁池或切换系统时调用。
func clear() -> void:
	if _lifecycle_transaction_active:
		push_warning("[UFramePool] 生命周期事务期间不能同步 clear()；请使用 call_deferred()")
		return
	_lifecycle_transaction_active = true
	for instance: Node in _owned:
		if is_instance_valid(instance):
			instance.queue_free()
	_available.clear()
	_active.clear()
	_owned.clear()
	_lifecycle_transaction_active = false
#endregion

#region 池状态查询
## 获取当前活跃实例数，调用成本固定。
func get_active_count() -> int:
	return _active.size()

## 获取当前由本池拥有的实例总数，调用成本固定。
func get_total_count() -> int:
	return _owned.size()
#endregion

#region 实例管理
## 从活跃映射中移除并返回最早取出的有效实例。 [br]
## 失效项会在遇到时惰性清理；没有活跃项时返回 [code]null[/code]。
func _take_oldest_active() -> Node:
	while not _active.is_empty():
		var oldest_value: Variant = null
		# Dictionary 保持插入顺序，因此第一项就是最早活跃的生命周期
		for candidate_value: Variant in _active:
			oldest_value = candidate_value
			break
		if oldest_value == null:
			return null
		_active.erase(oldest_value)
		if not is_instance_valid(oldest_value) or (oldest_value as Node).is_queued_for_deletion():
			_owned.erase(oldest_value)
			return null
		var instance := oldest_value as Node
		# 非本池所有的活跃项属于账本矛盾，不将它纳入新生命周期
		if not _owned.has(instance):
			return null
		return instance
	return null

## 对 [param instance] 调用归还钩子并停用。 [br]
## 钩子删除实例或将其移出本池时清理所有权并返回 [code]false[/code]，否则返回 [code]true[/code]。 [br][br]
## [param instance] : 本次操作的池化实例
func _end_instance_lifecycle(instance: Node) -> bool:
	if instance.has_method("_on_pool_release"):
		instance.call("_on_pool_release")
	if not is_instance_valid(instance) or instance.is_queued_for_deletion() or not _owned.has(instance):
		_owned.erase(instance)
		return false
	_set_instance_active(instance, false)
	return true

## 创建池化实例，将其作为 Pool 子节点加入场景树并立即停用；失败时返回 [code]null[/code]。
func _create_instance() -> Node:
	if pool_scene == null or (maximum_size > 0 and _owned.size() >= maximum_size):
		return null
	var instance := pool_scene.instantiate()
	if instance == null:
		return null
	_owned[instance] = true
	instance.tree_exiting.connect(_on_instance_exiting.bind(instance), CONNECT_ONE_SHOT)
	_set_instance_active(instance, false)
	add_child(instance)
	# 场景根的 ready 可能主动销毁或移走自身，不能继续登记为已创建实例
	if not is_instance_valid(instance) or instance.is_queued_for_deletion() or instance.get_parent() != self or not _owned.has(instance):
		_owned.erase(instance)
		return null
	instance_created.emit(instance)
	# 监听器可以销毁或移走新实例，此时创建事务应向调用方报告失败
	if not is_instance_valid(instance) or instance.is_queued_for_deletion() or instance.get_parent() != self or not _owned.has(instance):
		_owned.erase(instance)
		return null
	return instance

## 设置 [param instance] 的根节点处理模式和可见性，不遍历场景结构。 [br]
## Godot 会根据继承的处理模式和碰撞对象的 [code]disable_mode[/code] 自动退出或恢复物理模拟。 [br][br]
## [param instance] : 本次操作的池化实例 [br]
## [param active] : 是否启用实例
func _set_instance_active(instance: Node, active: bool) -> void:
	instance.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if instance is CanvasItem:
		(instance as CanvasItem).visible = active
	elif instance is Node3D:
		(instance as Node3D).visible = active

## 在容量与分类账本矛盾时完整修复内部引用。 [br]
## 正常取出、归还和溢出路径不会调用本方法。
func _repair_bookkeeping() -> void:
	var classified: Dictionary = {}
	# 先保留有效活跃项的原始顺序
	for instance: Variant in _active.keys():
		if (
			not is_instance_valid(instance)
			or (instance as Node).is_queued_for_deletion()
			or not _owned.has(instance)
		):
			_active.erase(instance)
			continue
		classified[instance] = true
	# 原地压缩空闲数组，避免反复 remove_at() 在异常账本上形成二次复杂度
	var write_index := 0
	for read_index in _available.size():
		var instance: Variant = _available[read_index]
		if (
			not is_instance_valid(instance)
			or (instance as Node).is_queued_for_deletion()
			or not _owned.has(instance)
			or classified.has(instance)
		):
			continue
		_available[write_index] = instance
		write_index += 1
		classified[instance] = true
	_available.resize(write_index)
	# 清理失效所有权，并将未分类实例视为活跃生命周期恢复到队尾
	for instance: Variant in _owned.keys():
		if not is_instance_valid(instance) or (instance as Node).is_queued_for_deletion():
			_owned.erase(instance)
			_active.erase(instance)
			continue
		if not classified.has(instance):
			_active[instance] = true

## 从全部容器移除即将退出场景树的 [param instance]。 [br][br]
## [param instance] : 本次操作的池化实例
func _on_instance_exiting(instance: Node) -> void:
	_available.erase(instance)
	_active.erase(instance)
	_owned.erase(instance)
#endregion
