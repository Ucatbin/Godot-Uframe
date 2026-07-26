extends Node

'''
描述：
	状态机组件
	自动发现子节点中的 State，管理状态切换和执行

用法：
	1. 把 StateMachine.gd 挂载到敌人/玩家节点上
	2. 在场景树里，给 StateMachine 添加若干子节点（每个都是一种状态）
	3. 每个状态脚本 extends State
	4. 代码里调用：state_machine.change_state("Idle")
'''
## 
class_name StateMachine

#region 变量
## [b]初始状态名[/b][br]
## 必须在 _ready 前设置，可在 Inspector 中填写
@export var initial_state: String = ""

## [b]当前正在运行的状态[/b][br]
## null 表示没有激活的状态
var current_state: State = null

## [b]存储所有子状态[/b][br]
## 映射: { state_name: State }
var _states: Dictionary = {}
#endregion

#region 生命周期
func _ready() -> void:
	if initial_state.is_empty():
		push_error("未设置初始状态")
		return

	# 扫描所有子节点，收集 State
	for child in get_children():
		if child is State:
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

#region 核心方法
## [b]切换状态[/b][br][br]
## [param state_name] : 目标状态名[br]
## [param data] : 传递给 on_enter() 的数据
func change_state(state_name: String, data := {}) -> void:
	if not _states.has(state_name):
		push_error("StateMachine: 找不到状态 [%s]" % state_name)
		return

	var new_state: State = _states[state_name]

	if current_state:
		current_state.on_exit()
	current_state = new_state
	current_state.on_enter(data)

	EventBus.send("state_changed", {
		"entity": get_parent(),
		"new_state": state_name
	})

## [b]获取当前状态名[/b][br][br]
## [color=cyan]返回 : [/color]当前状态名，无激活状态时返回 ""
func get_current_state_name() -> String:
	return current_state.state_name if current_state else ""

## [b]判断是否处于某状态[/b][br][br]
## [param state_name] : 状态名
func is_in_state(state_name: String) -> bool:
	return current_state and current_state.state_name == state_name
#endregion
