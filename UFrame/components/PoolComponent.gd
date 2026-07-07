extends Node

## [b]对象池组件[/b][br]
##
## 管理一个对象池。
## 在 Inspector 中配置 pool_scene 和 initial_size，节点 _ready 时自动创建池。[br]
## [br]用法：[br]
## 1. 在场景中添加 Node 节点[br]
## 2. 将 PoolComponent.gd 脚本拖到该节点上[br]
## 3. 在 Inspector 中填写 Pool Scene 和 Initial Size[br]
## 4. 节点就绪后直接调用 get_instance() / recycle()[br]
## [br]示例（节点挂载方式）：[br]
## [codeblock]
## # 场景树：
## # BulletManager (Node + PoolComponent)
## #
## # 代码中：
## func _ready():
##     var bullet = $BulletManager.get_instance()
##     bullet.global_position = muzzle.global_position
##
## func _on_bullet_exited_screen(bullet):
##     $BulletManager.recycle(bullet)
## [/codeblock]
class_name PoolComponent

#region 信号
## [b]从池中取出节点时触发[/b][br]
## [br]参数：[br]
## [param instance] : 被取出的节点
signal instance_spawned(instance: Node)

## [b]节点归还到池时触发[/b][br]
## [br]参数：[br]
## [param instance] : 被归还的节点
signal instance_recycled(instance: Node)
#endregion

#region 导出变量（Inspector 配置）
## [b]池化场景[/b][br]
## 要池化的 PackedScene
@export var pool_scene: PackedScene

## [b]预创建数量[/b][br]
## _ready 时自动创建的实例数量，默认 10
@export var initial_size: int = 10
#endregion

#region 变量
var _pool: Array[Node] = []
var _active: Array[Node] = []
#endregion

#region 生命周期
func _ready() -> void:
	if pool_scene == null:
		push_error("[PoolComponent] pool_scene 未配置，无法创建池")
		return
	_create_initial_pool()

func _exit_tree() -> void:
	clear()
#endregion

#region 获取/释放
## [b]获取节点[/b][br]
## [br]返回：[br]
## 激活后的节点实例；池空时自动扩展创建新实例
func get_instance() -> Node:
	var inst: Node = null

	if _pool.size() > 0:
		inst = _pool.pop_back()
	else:
		# 池空，动态扩展
		inst = pool_scene.instantiate()
		add_child(inst)
		print("[PoolComponent] 池已空，动态扩展创建新实例")

	inst.set_meta("in_pool", false)
	inst.visible = true
	inst.set_process(true)
	_active.append(inst)
	instance_spawned.emit(inst)
	return inst

## [b]回收节点[/b][br]
## [br]参数：[br]
## [param inst] : 要回收的节点
func recycle(inst: Node) -> void:
	if inst == null:
		return

	var idx: int = _active.find(inst)
	if idx != -1:
		_active.remove_at(idx)

	inst.set_meta("in_pool", true)
	inst.visible = false
	inst.set_process(false)
	if inst.has_method("_on_pool_recycle"):
		inst._on_pool_recycle()
	_pool.append(inst)
	instance_recycled.emit(inst)

## [b]节点自回收（节点内部调用）[/b][br]
## [br]参数：[br]
## [param inst] : 调用者自身
func recycle_self(inst: Node) -> void:
	if inst == null:
		return
	recycle(inst)

## [b]清空池，释放所有实例[/b]
func clear() -> void:
	for inst in _pool:
		if is_instance_valid(inst):
			inst.queue_free()
	for inst in _active:
		if is_instance_valid(inst):
			inst.queue_free()
	_pool.clear()
	_active.clear()
#endregion

#region 辅助方法
## [b]预加载池[/b]
func _create_initial_pool() -> void:
	for i in initial_size:
		var inst := pool_scene.instantiate() as Node
		inst.set_meta("in_pool", true)
		inst.visible = false
		inst.set_process(false)
		add_child(inst)
		_pool.append(inst)

	print("[PoolComponent] 池已创建，预创建 %d 个实例" % initial_size)
#endregion
