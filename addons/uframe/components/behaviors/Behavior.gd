extends Node

## 可组合行为基类
## 
## 必须作为 BehaviorManager 直属节点[br]
## 新建脚本继承 UFrameBehavior，只覆写当前状态需要的回调
class_name UFrameBehavior

#region 配置
## 是否启用
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
## [b]管理器引用[/b]
## 由 BehaviorManager 自动注入，无需手动修改
var manager: UFrameBehaviorManager = null

## [b]所属实体[/b]
## BehaviorManager 的父节点，通常是敌人/玩家节点[br]
## 由管理器层级自动注入，无需手动修改
var entity: Node = null

## [b]记录是否执行过on_enter()[/b]
var _behavior_entered := false
#endregion

#region 生命周期
## [b]行为开始时调用[/b]
func on_enter() -> void:
	pass

## [b]行为停止或离开场景树时调用[/b]
func on_exit() -> void:
	pass

## [b]普通帧更新[/b][br]
## 用于非物理逻辑[br][br]
## [param _delta] : 帧间隔
func on_update(_delta: float) -> void:
	pass

## [b]物理帧更新[/b][br]
## 用于物理逻辑[br][br]
## [param _delta] : 帧间隔
func on_physics_update(_delta: float) -> void:
	pass

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

#region 外部方法
func set_enabled(value: bool) -> void:
	enabled = value
#endregion

#region 私有方法
func _enter_behavior() -> void:
	if _behavior_entered:
		return
	_behavior_entered = true
	on_enter()

func _exit_behavior() -> void:
	if not _behavior_entered:
		return
	_behavior_entered = false
	on_exit()

func _sync_processing() -> void:
	set_process(_behavior_entered)
	set_physics_process(_behavior_entered)

func _bind_to_manager(new_manager: UFrameBehaviorManager, new_entity: Node) -> void:
	manager = new_manager
	entity = new_entity
	if is_node_ready() and is_inside_tree():
		_activate_when_entity_is_ready()

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
