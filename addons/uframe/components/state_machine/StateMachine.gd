extends Node

## 节点式有限状态机组件
##
## 将多个 [UFrameState] 作为直属子节点，并设置 [member initial_state][br]
## 状态机会向当前状态转发普通帧和物理帧更新，状态只需覆写需要的回调
class_name UFrameStateMachine

#region 信号
## 状态切换完成[br]
## 新状态的 [method UFrameState.on_enter] 执行后发出[br][br]
## 推荐使用 [method connect_state_changed] 订阅，避免晚于初始化连接时漏掉初始状态[br][br]
## [param previous] : 上一个状态名[br]
## [param current] : 当前状态名
signal state_changed(previous: StringName, current: StringName)
#endregion

#region 配置
## 初始状态名[br]
## 必须在初始化前设置，并对应一个直属 [UFrameState] 子节点
@export var initial_state: StringName
#endregion

#region 运行时状态
## 当前正在运行的状态[br]
var current_state: UFrameState = null

## 状态表[br][br]
## 状态名 -> [UFrameState]
var _states: Dictionary[StringName, UFrameState] = {}
#endregion

#region 生命周期
func _ready() -> void:
	if initial_state.is_empty():
		push_error("未设置初始状态")
		return
	# 自动获取状态并注入
	for child in get_children():
		if child is UFrameState:
			_states[child.state_name] = child
			child.state_machine = self
			child.entity = get_parent()
	change_state(initial_state)

func _process(delta: float) -> void:
	if current_state:
		current_state.on_update(delta)

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.on_physics_update(delta)
#endregion

#region 主要方法
## 切换当前状态[br]
## 目标不存在或已经是当前状态时保持不变[br][br]
## [param state_name] : 目标状态名[br]
## [param data] : 传递给 [method UFrameState.on_enter] 的数据
func change_state(state_name: StringName, data := {}) -> void:
	if not _states.has(state_name):
		push_error("[UFrameStateMachine] 找不到状态：%s" % state_name)
		return
	var new_state: UFrameState = _states[state_name]
	if new_state == current_state:
		return
	var previous_state := get_current_state_name()
	if current_state:
		current_state.on_exit()
	current_state = new_state
	current_state.on_enter(data)
	state_changed.emit(previous_state, StringName(state_name))

## 连接状态变化回调，并同步状态[br]
## 防止初始状态切换信号无法正确送达，初始化后连接时，会立即回调一次空状态到当前状态[br]
## 重复连接同一回调时不会重复连接或再次同步[br][br]
## [param callback] : 接收 [code]previous[/code] 和 [code]current[/code] 两个状态名
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

#region 查询方法
## 获取当前状态名；没有激活状态时返回空 [StringName]
func get_current_state_name() -> StringName:
	return current_state.state_name if current_state else StringName()

## 判断当前状态[br][br]
## [param state_name] : 需要检查的状态名
func is_in_state(state_name: StringName) -> bool:
	return current_state and current_state.state_name == state_name
#endregion
