extends Node

## [b]对象池组件[/b][br][br]
## [br]用法：[br]
## 1. 在场景中添加 Node 节点[br]
## 2. 将 PoolComponent.gd 脚本拖到该节点上[br]
## 3. 在 Inspector 中填写 Pool Scene 和 Initial Size[br]
## 4. 节点就绪后直接调用 get_instance() / release()[br]
## [br]示例：
## [codeblock]
## func _ready():
##     var bullet = $BulletManager.get_instance()
##     bullet.global_position = muzzle.global_position
##
## func _on_bullet_exited_screen(bullet):
##     $BulletManager.release(bullet)
## [/codeblock]
class_name PoolComponent

#region 信号
## [b]从池中取出节点时触发[/b][br][br]
## [param instance] : 被取出的节点
signal instance_spawned(instance: Node)

## [b]节点归还到池时触发[/b][br][br]
## [param instance] : 被归还的节点
signal instance_released(instance: Node)
#endregion

#region 配置变量
## [b]池化对象[/b]
@export var pool_scene: PackedScene

## [b]预创建数量[/b]
@export var initial_size: int = 10
#endregion

#region 变量
var _pool: Array[Node] = []
var _active: Dictionary = {}
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

#region 公共方法
## [b]获取节点[/b][br]
## [color=cyan]返回：[/color]激活后的节点实例
func get_instance() -> Node:
	var inst: Node = null

	if _pool.size() > 0:
		inst = _pool.pop_back()
	else:
		inst = pool_scene.instantiate()
		add_child(inst)
		print("[PoolComponent] 池已空，动态扩展创建新实例")

	inst.visible = true
	inst.set_process(true)
	_active[inst] = true
	instance_spawned.emit(inst)
	return inst

## [b]释放节点[/b][br][br]
## [param inst] : 要释放的节点
func release(inst: Node) -> void:
	if inst == null:
		return

	if _active.has(inst):
		_active.erase(inst)

	inst.visible = false
	inst.set_process(false)
	if inst.has_method("_on_pool_release"):
		inst._on_pool_release()
	_pool.append(inst)
	instance_released.emit(inst)

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

#region 内部方法
## [b]预加载池[/b]
func _create_initial_pool() -> void:
	for i in initial_size:
		var inst := pool_scene.instantiate() as Node
		inst.visible = false
		inst.set_process(false)
		add_child(inst)
		_pool.append(inst)

	print("[PoolComponent] 池已创建，预创建 %d 个实例" % initial_size)
#endregion
