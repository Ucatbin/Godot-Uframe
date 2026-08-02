extends Node

## 通用场景对象池组件。
##
## 将本脚本挂到一个 Node，并在 Inspector 中设置 Pool Scene。[br]
## 获取对象使用 [code]acquire()[/code]，不用时使用 [code]release(instance)[/code] 归还。[br]
## 适合子弹、伤害数字、粒子等频繁创建和销毁的对象。
## [codeblock]
## var bullet := $BulletPool.acquire()
## if bullet:
##     bullet.global_position = muzzle.global_position
##
## $BulletPool.release(bullet)
## [/codeblock]
## 池化对象可以实现 _on_pool_acquire() 和 _on_pool_release() 来重置自身状态。
class_name UFramePool

## 达到 maximum_size、所有实例又都在使用时的处理方式。
enum OverflowPolicy {
	## 保持现有安全行为：acquire() 返回 null，由调用方决定跳过还是稍后重试。
	RETURN_NULL,
	## 中断并复用“当前活跃周期最早开始”的实例，适合允许被截断的粒子和装饰。
	RECYCLE_OLDEST_ACTIVE,
}

## 闲置对象的碰撞配置保存在 metadata 中，重新取出时恢复场景原始值。
## 使用框架专用前缀，避免与游戏自己的 metadata 重名。
const _META_LAYER_2D := &"_uframe_pool_layer_2d"
const _META_MASK_2D := &"_uframe_pool_mask_2d"
const _META_LAYER_3D := &"_uframe_pool_layer_3d"
const _META_MASK_3D := &"_uframe_pool_mask_3d"
const _META_MONITORING := &"_uframe_pool_monitoring"
const _META_MONITORABLE := &"_uframe_pool_monitorable"

## 成功取出一个实例时发出。
signal instance_acquired(instance: Node)
## 成功归还一个实例时发出。
signal instance_released(instance: Node)
## 首次创建一个实例时发出。预热阶段创建的实例也会触发。
signal instance_created(instance: Node)
## 达到上限后完成一次强制复用时发出；不会额外触发 instance_created。
signal instance_recycled(instance: Node)

## 池中要创建的场景。必须设置。
@export var pool_scene: PackedScene
## 场景启动时预创建的数量。0 表示不预创建。
@export_range(0, 100000) var initial_size := 0
## 池允许拥有的最大实例数。0 表示没有上限。
@export_range(0, 100000) var maximum_size := 0
## 达到上限且没有空闲实例时的策略。默认返回 null，保持最安全且兼容旧项目。
## “复用最早活跃实例”只适合粒子、拖尾、装饰等允许提前结束的对象。
@export_enum("达到上限返回空值", "复用最早活跃实例") var overflow_policy: int = OverflowPolicy.RETURN_NULL

## 当前空闲、可以再次取出的实例。
var _available: Array[Node] = []
## 当前已被取出的实例集合。
## value 是该实例最近一次 acquire() 的递增顺序，用于精确定义“最早活跃”。
var _active: Dictionary = {}
## 本池创建过的全部实例，用于拒绝归还其他池的对象。
var _owned: Dictionary = {}
var _acquire_order := 0

func _ready() -> void:
	if pool_scene == null:
		push_error("[UFramePool] 必须设置 pool_scene")
		return
	var prewarm_count := initial_size if maximum_size == 0 else mini(initial_size, maximum_size)
	for _index in prewarm_count:
		var instance := _create_instance()
		if instance:
			_available.append(instance)

## 从池中获取实例。达到 maximum_size 且没有空闲对象时，按照 overflow_policy
## 返回 null 或复用最早取得且尚未归还的实例。
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

## 将实例归还到池中。
## 成功返回 true；重复归还或归还非本池对象会返回 false。
func release(instance: Node) -> bool:
	if not is_instance_valid(instance) or instance.is_queued_for_deletion() or not _owned.has(instance) or not _active.erase(instance):
		return false
	_deactivate_instance(instance, true)
	return true

## 释放本池创建的全部实例。通常只在销毁池或切换系统时调用。
func clear() -> void:
	for instance: Node in _owned:
		if is_instance_valid(instance):
			instance.queue_free()
	_available.clear()
	_active.clear()
	_owned.clear()
	_acquire_order = 0

## acquire() 的兼容别名。新代码建议直接使用 acquire()。
func get_instance() -> Node:
	return acquire()

## 当前已取出、正在使用的实例数量。tree_exiting 会维护集合，因此本查询为 O(1)。
func get_active_count() -> int:
	return _active.size()

## 当前池拥有的实例总数。queue_free 的实例会在退出场景树时自动移除。
func get_total_count() -> int:
	return _owned.size()


## 取出活跃周期最早的实例，并先从 active 集合移除。
## 只在池已满且显式启用回收策略时扫描；普通获取与归还没有额外遍历。
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


## 执行一次完整归还生命周期。cache_instance=false 表示实例马上会被同一次
## acquire() 重新启用，因此无需先塞入 available 再弹出。
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

func _set_instance_active(instance: Node, active: bool) -> void:
	instance.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if instance is CanvasItem:
		(instance as CanvasItem).visible = active
	elif instance is Node3D:
		(instance as Node3D).visible = active
	_set_collision_tree_active(instance, active)

## 递归停用实体根节点以及所有后代碰撞对象。[br]
## 这样池化实体可以采用“Entity 根节点 + Hitbox/Hurtbox 子组件”的组合结构，
## 闲置时不会留下不可见的物理实体或 Area 信号。
func _set_collision_tree_active(node: Node, active: bool) -> void:
	if node is CollisionObject2D:
		_set_collision_object_2d_active(node as CollisionObject2D, active)
	elif node is CollisionObject3D:
		_set_collision_object_3d_active(node as CollisionObject3D, active)
	for child: Node in node.get_children():
		_set_collision_tree_active(child, active)

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

func _prune_invalid_instances() -> void:
	for index in range(_available.size() - 1, -1, -1):
		var instance: Variant = _available[index]
		if not is_instance_valid(instance) or instance.is_queued_for_deletion():
			_available.remove_at(index)
	for instance: Variant in _owned.keys():
		if not is_instance_valid(instance) or instance.is_queued_for_deletion():
			_owned.erase(instance)
			_active.erase(instance)

func _on_instance_exiting(instance: Node) -> void:
	_available.erase(instance)
	_active.erase(instance)
	_owned.erase(instance)
