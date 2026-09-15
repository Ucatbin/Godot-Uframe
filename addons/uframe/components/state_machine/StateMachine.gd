extends Node

## 节点式有限状态机组件。
##
## 负责收集直属 [UFrameState]、注入实体依赖、执行互斥切换，并转发普通帧与物理帧更新。
class_name UFrameStateMachine

#region 信号
## 新状态的 [method UFrameState.on_enter] 执行完成后发出。 [br]
## 使用 [method connect_state_changed] 订阅，避免初始化后连接时漏掉初始状态。 [br][br]
## [param previous] : 上一个状态 [br]
## [param current] : 当前状态
signal state_changed(previous: StringName, current: StringName)
#endregion

#region Inspector 配置
## 初始状态名；必须在初始化前设置，并对应一个直属 [UFrameState] 子节点。
@export var initial_state: StringName
#endregion

#region 运行时状态
## 当前正在运行的状态；初始化失败时为 [code]null[/code]。
var current_state: UFrameState = null

## 状态名到直属 [UFrameState] 的一次性映射。
var _states: Dictionary[StringName, UFrameState] = {}

## 切换回调和通知执行期间禁止同步重入，保证退出、进入和通知的顺序一致。
var _changing_state := false
#endregion

#region 生命周期
## 收集全部直属状态、统一注入依赖，再进入 [member initial_state]。
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if initial_state.is_empty():
		push_error("[UFrameStateMachine] 未设置 initial_state")
		return
	# 先收集完整状态表，保证任何状态在 on_setup() 中都能查询其他状态
	var states_to_setup: Array[UFrameState] = []
	for child in get_children():
		if child is UFrameState:
			var state := child as UFrameState
			_states[state.state_name] = state
			states_to_setup.append(state)
	# 状态表完整后再统一注入依赖，每个状态只装配一次
	var owner_entity := get_parent()
	for state in states_to_setup:
		state.setup(self, owner_entity)
	change_state(initial_state)

func _process(delta: float) -> void:
	if current_state:
		current_state.on_update(delta)

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.on_physics_update(delta)
#endregion

#region 状态切换
## 切换到新状态。 [br]
## on_enter、on_exit 或变化监听器需要继续切换时，请使用 [method Object.call_deferred]。 [br][br]
## [param state_name] : 新状态名 [br]
## [param data] : 传递给新状态的数据
func change_state(state_name: StringName, data: Dictionary = {}) -> void:
	if _changing_state:
		push_warning("[UFrameStateMachine] 切换回调期间不能同步切换；请使用 call_deferred()")
		return
	if not _states.has(state_name):
		push_error("[UFrameStateMachine] 找不到状态：%s" % state_name)
		return
	var new_state: UFrameState = _states[state_name]
	if new_state == current_state:
		return
	_changing_state = true
	var previous_state := get_current_state_name()
	if current_state:
		current_state.on_exit()
	else:
		set_process(true)
		set_physics_process(true)
	current_state = new_state
	current_state.on_enter(data)
	state_changed.emit(previous_state, StringName(state_name))
	_changing_state = false

## 连接接收 [code]previous[/code] 与 [code]current[/code] 的状态变化。 [br][br]
## [param callback] : 触发回调
func connect_state_changed(callback: Callable) -> void:
	if not callback.is_valid():
		push_error("[UFrameStateMachine] 状态回调无效")
		return
	if state_changed.is_connected(callback):
		return
	state_changed.connect(callback)
	if current_state:
		callback.call(StringName(), get_current_state_name())
#endregion

#region 状态查询
## 获取当前状态名；没有激活状态时返回空 [StringName]。
func get_current_state_name() -> StringName:
	return current_state.state_name if current_state else StringName()

## 判断当前状态是否为 [param state_name]。 [br][br]
## [param state_name] : 状态名
func is_in_state(state_name: StringName) -> bool:
	return current_state and current_state.state_name == state_name
#endregion
