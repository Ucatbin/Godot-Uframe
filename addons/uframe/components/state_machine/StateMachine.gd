extends Node

## 节点式有限状态机组件
##
## 将多个 [UFrameState] 作为直属子节点，并设置 [member initial_state][br]
## 状态机会向当前状态转发普通帧和物理帧更新，状态只需覆写需要的回调
class_name UFrameStateMachine

#region 信号
## [b]状态切换完成[/b][br]
## 新状态的 [method UFrameState.on_enter] 执行后发出[br][br]
## [param previous] : 上一个状态名[br]
## [param current] : 当前状态名
signal state_changed(previous: StringName, current: StringName)
#endregion

#region 配置
## [b]初始状态名[/b][br]
## 必须在初始化前设置，并对应一个直属 [UFrameState] 子节点
@export var initial_state: StringName
#endregion

#region 运行时状态
## [b]当前正在运行的状态[/b][br]
var current_state: UFrameState = null

## [b]状态表[/b][br][br]
## [color=cyan]映射：[/color]状态名 → [UFrameState]。
var _states: Dictionary[StringName, UFrameState] = {}
#endregion

#region 生命周期
func _ready() -> void:
	if initial_state.is_empty():
		push_error("未设置初始状态")
		return
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
## [b]切换当前状态[/b][br]
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
	var previous := get_current_state_name()
	if current_state:
		current_state.on_exit()
	current_state = new_state
	current_state.on_enter(data)
	state_changed.emit(previous, StringName(state_name))
#endregion

#region 查询方法
## [b]获取当前状态名[/b][br]
## 没有激活状态时返回空 [StringName]
func get_current_state_name() -> StringName:
	return current_state.state_name if current_state else StringName()

## [b]判断当前状态[/b][br][br]
## [param state_name] : 需要检查的状态名
func is_in_state(state_name: StringName) -> bool:
	return current_state and current_state.state_name == state_name
#endregion
