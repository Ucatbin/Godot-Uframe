extends Node

## 可并行启停的实体行为基类。
##
## 仅关注行为本身，不负责行为之间的互斥切换；互斥玩法逻辑应使用 [UFrameStateMachine]。
class_name UFrameBehavior

#region Inspector 配置
## 是否启用行为。 [br]
## 运行时修改会自动进入或退出行为，并同步帧处理状态。
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

#region 依赖引用
## 所属行为管理器，由 [UFrameBehaviorManager] 自动注入。
var manager: UFrameBehaviorManager = null

## 所属实体；由 [UFrameBehaviorManager] 自动注入。
var entity: Node = null
#endregion

#region 运行时状态
## 行为是否已经进入，用于保证 [method on_enter] 与 [method on_exit] 成对执行。
var _behavior_entered := false
#endregion

#region 可覆写回调
## 行为启用且所属实体 ready 后调用。
func on_enter() -> void:
	pass

## 禁用行为或离开场景树时调用。
func on_exit() -> void:
	pass

## 由普通帧回调转发。 [br][br]
## [param _delta] : 帧间隔
func on_update(_delta: float) -> void:
	pass

## 由物理帧回调转发。 [br][br]
## [param _delta] : 物理帧间隔
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

#region 行为控制
## 设置行为是否启用；节点就绪后会同步进入或退出生命周期。 [br][br]
## [param value] : 启用状态
func set_enabled(value: bool) -> void:
	enabled = value
#endregion

#region 生命周期控制
## 进入行为生命周期；已经进入时不会重复调用 [method on_enter]。
func _enter_behavior() -> void:
	if _behavior_entered:
		return
	_behavior_entered = true
	on_enter()

## 退出行为生命周期；尚未进入时不会调用 [method on_exit]。
func _exit_behavior() -> void:
	if not _behavior_entered:
		return
	_behavior_entered = false
	on_exit()

## 根据行为是否已经进入，同步普通帧与物理帧处理状态。
func _sync_processing() -> void:
	set_process(_behavior_entered)
	set_physics_process(_behavior_entered)

## 由 [UFrameBehaviorManager] 为直属子节点注入管理器和实体。 [br][br]
## [param new_manager] : 所属管理器 [br]
## [param new_entity] : 所属实体
func _bind_to_manager(new_manager: UFrameBehaviorManager, new_entity: Node) -> void:
	manager = new_manager
	entity = new_entity
	if is_node_ready() and is_inside_tree():
		_activate_when_entity_is_ready()

## 等待实体 ready 后激活行为；等待期间绑定关系变化时取消本次激活。
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
