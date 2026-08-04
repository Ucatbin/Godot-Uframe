extends Node

## 可组合实体行为基类
##
## 必须作为 [UFrameBehaviorManager] 的直属子节点使用[br]
## 具体行为继承本类后，只需覆写需要的生命周期和帧更新回调
class_name UFrameBehavior

#region 配置
## [b]是否启用[/b][br]
## 运行时修改会自动进入或退出行为，并同步帧处理状态
@export var enabled := true:
	set(value):
		if enabled == value:
			return
		enabled = value
		if (
			not is_node_ready()
			or not is_inside_tree()
			or manager == null
			or entity == null
			or not entity.is_node_ready()
		):
			return
		if enabled:
			_enter_behavior()
		else:
			_exit_behavior()
		_sync_processing()
#endregion

#region 运行时状态
## [b]管理器引用[/b][br]
## 由 [UFrameBehaviorManager] 自动注入
var manager: UFrameBehaviorManager = null

## [b]所属实体[/b][br]
## 管理器的父节点，通常是玩家或敌人实体；由 [UFrameBehaviorManager] 自动注入
var entity: Node = null

## [b]行为进入状态[/b][br]
## 用于保证 [method on_enter] 与 [method on_exit] 成对执行
var _behavior_entered := false
#endregion

#region 可覆写回调
## [b]进入行为[/b]
func on_enter() -> void:
	pass

## [b]退出行为[/b][br]
## 禁用行为或离开场景树时调用
func on_exit() -> void:
	pass

## [b]更新普通帧[/b][br]
## 仅在行为进入后执行[br][br]
## [param _delta] : 帧间隔
func on_update(_delta: float) -> void:
	pass

## [b]更新物理帧[/b][br]
## 仅在行为进入后执行[br][br]
## [param _delta] : 帧间隔
func on_physics_update(_delta: float) -> void:
	pass
#endregion

#region 生命周期
func _enter_tree() -> void:
	# Manager 会在 child_entered_tree 中重新注入；等待注入完成后再恢复生命周期。
	if is_node_ready():
		_sync_processing()

func _ready() -> void:
	_sync_processing()
	if manager == null or entity == null:
		push_warning("[UFrameBehavior] %s 必须挂载在 UFrameBehaviorManager 下" % name)
		return
	_activate_when_entity_is_ready()

func _exit_tree() -> void:
	_exit_behavior()
	set_process(false)
	set_physics_process(false)
	manager = null
	entity = null

func _process(delta: float) -> void:
	on_update(delta)

func _physics_process(delta: float) -> void:
	on_physics_update(delta)
#endregion

#region 主要方法
## [b]设置启用状态[/b][br][br]
## [param value] : 是否启用行为
func set_enabled(value: bool) -> void:
	enabled = value
#endregion

#region 内部方法
## [b]进入行为生命周期[/b][br]
## 已经进入时不重复执行
func _enter_behavior() -> void:
	if _behavior_entered:
		return
	_behavior_entered = true
	on_enter()

## [b]退出行为生命周期[/b][br]
## 尚未进入时不执行
func _exit_behavior() -> void:
	if not _behavior_entered:
		return
	_behavior_entered = false
	on_exit()

## [b]同步帧处理状态[/b][br]
## 仅在行为已经进入时启用普通帧和物理帧回调
func _sync_processing() -> void:
	set_process(_behavior_entered)
	set_physics_process(_behavior_entered)

## [b]绑定行为管理器[/b][br]
## 由 [UFrameBehaviorManager] 为直属子节点调用[br][br]
## [param new_manager] : 所属行为管理器[br]
## [param new_entity] : 管理器所属实体
func _bind_to_manager(new_manager: UFrameBehaviorManager, new_entity: Node) -> void:
	manager = new_manager
	entity = new_entity
	if is_node_ready() and is_inside_tree():
		_activate_when_entity_is_ready()

## [b]等待实体就绪并激活[/b][br]
## 等待期间绑定关系发生变化时取消本次激活
func _activate_when_entity_is_ready() -> void:
	var expected_manager := manager
	var expected_entity := entity
	if expected_manager == null or expected_entity == null:
		return
	if not expected_entity.is_node_ready():
		await expected_entity.ready
	if (
		not is_inside_tree()
		or manager != expected_manager
		or entity != expected_entity
	):
		return
	if enabled:
		_enter_behavior()
	_sync_processing()
#endregion
