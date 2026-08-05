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
class_name UFramePool

#region 枚举
## [b]容量溢出策略[/b]
enum OverflowPolicy {
	## [method acquire] 返回 [code]null[/code]，由调用方决定跳过或重试。
	RETURN_NULL,
	## 中断并复用当前活跃周期最早开始的实例。
	RECYCLE_OLDEST_ACTIVE,
}
#endregion

#region 常量
## [b]2D 碰撞层元数据键[/b]
const _META_LAYER_2D := &"_uframe_pool_layer_2d"
## [b]2D 碰撞遮罩元数据键[/b]
const _META_MASK_2D := &"_uframe_pool_mask_2d"
## [b]3D 碰撞层元数据键[/b]
const _META_LAYER_3D := &"_uframe_pool_layer_3d"
## [b]3D 碰撞遮罩元数据键[/b]
const _META_MASK_3D := &"_uframe_pool_mask_3d"
## [b]区域监测状态元数据键[/b]
const _META_MONITORING := &"_uframe_pool_monitoring"
## [b]区域可监测状态元数据键[/b][br]
## 框架前缀用于避免与游戏元数据重名
const _META_MONITORABLE := &"_uframe_pool_monitorable"
#endregion

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

## [b]实例强制复用完成[/b][br]
## 不会额外发出 [signal instance_created][br][br]
## [param instance] : 被复用的实例
signal instance_recycled(instance: Node)
#endregion

#region 配置
## [b]池化场景[/b][br]
## 必须设置
@export var pool_scene: PackedScene

## [b]预热数量[/b][br]
## [code]0[/code] 表示不预创建
@export_range(0, 100000) var initial_size := 0

## [b]最大实例数[/b][br]
## [code]0[/code] 表示没有上限
@export_range(0, 100000) var maximum_size := 0

## [b]容量溢出策略[/b][br]
## 强制复用只适合粒子、拖尾和装饰等允许提前结束的对象
@export_enum("达到上限返回空值", "复用最早活跃实例") var overflow_policy: int = OverflowPolicy.RETURN_NULL
#endregion

#region 运行时状态
## [b]空闲实例[/b]
var _available: Array[Node] = []

## [b]活跃实例[/b][br][br]
## [color=cyan]映射：[/color]实例 → 最近一次 [method acquire] 的递增顺序。
var _active: Dictionary = {}

## [b]本池实例[/b][br][br]
## [color=cyan]集合：[/color]本池创建且尚未退出场景树的全部实例。
var _owned: Dictionary = {}

## [b]取出顺序计数[/b]
var _acquire_order := 0
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
## 达到 [member maximum_size] 且没有空闲对象时，根据 [member overflow_policy] 返回 [code]null[/code] 或强制复用
func acquire() -> Node:
	if pool_scene == null:
		return null
	var instance: Node = null
	var recycled := false
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
			elif overflow_policy == OverflowPolicy.RECYCLE_OLDEST_ACTIVE:
				instance = _take_oldest_active()
				if is_instance_valid(instance):
					recycled = _deactivate_instance(instance, false)
					if not recycled:
						# 生命周期钩子若主动销毁了旧实例，容量已经空出，直接补建一个。
						instance = _create_instance() if _owned.size() < maximum_size else null
			else:
				return null
	if not is_instance_valid(instance) or instance.is_queued_for_deletion():
		return null
	_acquire_order += 1
	_active[instance] = _acquire_order
	_set_instance_active(instance, true)
	if instance.has_method("_on_pool_acquire"):
		instance.call("_on_pool_acquire")
	instance_acquired.emit(instance)
	if recycled:
		instance_recycled.emit(instance)
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
	_acquire_order = 0

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
## 只在池已满且启用强制复用时扫描，并先从活跃集合移除
func _take_oldest_active() -> Node:
	var oldest: Node = null
	var oldest_order := 9223372036854775807
	for candidate_value: Variant in _active:
		var candidate := candidate_value as Node
		if not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
			continue
		var order := int(_active.get(candidate, oldest_order))
		if order < oldest_order:
			oldest = candidate
			oldest_order = order
	if oldest:
		_active.erase(oldest)
	return oldest

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
## 同步处理模式、可见性与后代碰撞对象[br][br]
## [param instance] : 需要设置的实例[br]
## [param active] : 是否启用实例
func _set_instance_active(instance: Node, active: bool) -> void:
	instance.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if instance is CanvasItem:
		(instance as CanvasItem).visible = active
	elif instance is Node3D:
		(instance as Node3D).visible = active
	_set_collision_tree_active(instance, active)

## [b]设置碰撞树活动状态[/b][br]
## 递归处理实体根节点和全部后代，使组合实体闲置时不保留物理交互[br][br]
## [param node] : 当前递归节点[br]
## [param active] : 是否启用碰撞
func _set_collision_tree_active(node: Node, active: bool) -> void:
	if node is CollisionObject2D:
		_set_collision_object_2d_active(node as CollisionObject2D, active)
	elif node is CollisionObject3D:
		_set_collision_object_3d_active(node as CollisionObject3D, active)
	for child: Node in node.get_children():
		_set_collision_tree_active(child, active)

## [b]设置 2D 碰撞对象状态[/b][br]
## 首次处理时保存原始碰撞层、遮罩与区域监测配置[br][br]
## [param object] : 2D 碰撞对象[br]
## [param active] : 是否恢复原始配置
func _set_collision_object_2d_active(object: CollisionObject2D, active: bool) -> void:
	if not object.has_meta(_META_LAYER_2D):
		object.set_meta(_META_LAYER_2D, object.collision_layer)
		object.set_meta(_META_MASK_2D, object.collision_mask)
	object.collision_layer = int(object.get_meta(_META_LAYER_2D)) if active else 0
	object.collision_mask = int(object.get_meta(_META_MASK_2D)) if active else 0
	if object is Area2D:
		var area := object as Area2D
		if not area.has_meta(_META_MONITORING):
			area.set_meta(_META_MONITORING, area.monitoring)
			area.set_meta(_META_MONITORABLE, area.monitorable)
		area.monitoring = bool(area.get_meta(_META_MONITORING)) if active else false
		area.monitorable = bool(area.get_meta(_META_MONITORABLE)) if active else false

## [b]设置 3D 碰撞对象状态[/b][br]
## 首次处理时保存原始碰撞层、遮罩与区域监测配置[br][br]
## [param object] : 3D 碰撞对象[br]
## [param active] : 是否恢复原始配置
func _set_collision_object_3d_active(object: CollisionObject3D, active: bool) -> void:
	if not object.has_meta(_META_LAYER_3D):
		object.set_meta(_META_LAYER_3D, object.collision_layer)
		object.set_meta(_META_MASK_3D, object.collision_mask)
	object.collision_layer = int(object.get_meta(_META_LAYER_3D)) if active else 0
	object.collision_mask = int(object.get_meta(_META_MASK_3D)) if active else 0
	if object is Area3D:
		var area := object as Area3D
		if not area.has_meta(_META_MONITORING):
			area.set_meta(_META_MONITORING, area.monitoring)
			area.set_meta(_META_MONITORABLE, area.monitorable)
		area.monitoring = bool(area.get_meta(_META_MONITORING)) if active else false
		area.monitorable = bool(area.get_meta(_META_MONITORABLE)) if active else false

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
