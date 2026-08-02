extends Node

## 节点式有限状态机
##
## 将多个 UFrameState 子节点放在本节点下，并设置 Initial State
## 状态机会同时转发普通帧和物理帧更新；每个状态只需覆写自己需要的回调
class_name UFrameStateMachine

#region 配置
## [b]初始状态名[/b][br]
## 必须在 _ready 前设置，可在 Inspector 中填写
@export var initial_state: StringName

## [b]当前正在运行的状态[/b][br]
## null 表示没有激活的状态
var current_state: UFrameState = null

## [b]存储所有子状态[/b][br]
## 映射：state_name → UFrameState
var _states: Dictionary[StringName, UFrameState] = {}
#endregion

## 状态成功切换后发出
signal state_changed(previous: StringName, current: StringName)

#region 生命周期
func _ready() -> void:
	if initial_state.is_empty():
		push_error("未设置初始状态")
		return

	# 扫描所有子节点，收集 State。
	for child in get_children():
		if child is UFrameState:
			_states[child.state_name] = child
			child.state_machine = self
			child.entity = get_parent()

	# 切换到初始状态
	change_state(initial_state)

func _process(delta: float) -> void:
	if current_state:
		current_state.on_update(delta)

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.on_physics_update(delta)
#endregion

#region 外部方法
## [b]切换状态[/b][br][br]
## [param state_name] : 目标状态名[br]
## [param data] : 传递给 on_enter() 的数据
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

## [b]获取当前状态名[/b][br][br]
## [color=cyan]返回 : [/color]当前状态名，无激活状态时返回 ""
func get_current_state_name() -> StringName:
	return current_state.state_name if current_state else StringName()

## [b]判断是否处于某状态[/b][br][br]
## [param state_name] : 状态名
func is_in_state(state_name: StringName) -> bool:
	return current_state and current_state.state_name == state_name
#endregion
