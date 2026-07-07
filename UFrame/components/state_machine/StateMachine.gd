# ============================================================
# StateMachine.gd  —  状态机组件（挂载版）
# 用法：
#   1. 把 StateMachine.gd 挂载到 敌人/玩家 节点上
#   2. 在场景树里，给 StateMachine 添加若干子节点（每个都是一种状态）
#   3. 每个状态脚本 extends "res://UcatFrameWork/state_machine/State.gd"
#   4. 代码里调用：state_machine.change_state("Idle")
# ============================================================

class_name StateMachine
extends Node

## 初始状态名（必须在 _ready 前设置，可以在 Inspector 里填）
@export var initial_state: String = ""

#region 状态管理

## 当前正在运行的状态（null 表示没有激活的状态）
var current_state: State = null

## 存储所有子状态 { state_name: State }
var _states: Dictionary = {}

#endregion

#region 生命周期

func _ready() -> void:
	# 扫描所有子节点，收集 State
	for child in get_children():
		if child is State:
			_states[child.state_name] = child
			child.state_machine = self
			child.entity = get_parent()
			child.set_process(false)   # 先全部暂停

	# 切换到初始状态
	if not initial_state.is_empty():
		change_state(initial_state)

#endregion

#region 核心方法（给外部调用）

## 切换状态（会调用旧状态的 on_exit，再调用新状态的 on_enter）
func change_state(state_name: String, data := {}) -> void:
	if not _states.has(state_name):
		push_error("StateMachine: 找不到状态 [%s]" % state_name)
		return

	var new_state: State = _states[state_name]

	# 退出旧状态
	if current_state:
		current_state.set_process(false)
		current_state.on_exit()

	# 进入新状态
	current_state = new_state
	current_state.set_process(true)
	current_state.on_enter(data)

	EventBus.emit("state_changed", {
		"entity": get_parent(),
		"new_state": state_name
	})

## 获取当前状态名（方便外部判断）
func get_current_state_name() -> String:
	return current_state.state_name if current_state else ""

## 判断当前是否处于某状态
func is_in_state(state_name: String) -> bool:
	return current_state and current_state.state_name == state_name

#endregion
