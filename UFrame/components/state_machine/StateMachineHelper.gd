extends RefCounted

'''
描述：
	纯代码版状态机
	不依赖场景树，适合在 _process 中手动调用，或不可挂节点的地方

用法：
	var fsm = StateMachineHelper.new()
	fsm.add_state("Idle", func(_d): pass, func(_d): pass, func(): pass)
	fsm.add_state("Attack", ..., ..., ...)
	fsm.change_state("Idle")

	func _process(delta):
	    fsm.update(delta)
'''

class_name StateMachineHelper

#region 变量
## [b]当前状态名[/b]
var current_state: String = ""

## [b]存储所有状态[/b][br]
## 映射: { state_name: { enter, exit, update } }
var _states: Dictionary = {}
#endregion

#region 核心 API
## [b]添加一个状态[/b][br]
## enter/update/exit 都可以传空的 Callable[br]
## [br]参数：[br]
## [param state_name] : 状态名[br]
## [param on_enter] : 进入回调[br]
## [param on_update] : 每帧更新回调[br]
## [param on_exit] : 退出回调
func add_state(
	state_name: String,
	on_enter: Callable = Callable(),
	on_update: Callable = Callable(),
	on_exit: Callable = Callable()
) -> void:
	_states[state_name] = {
		"enter": on_enter,
		"update": on_update,
		"exit": on_exit
	}

## [b]切换状态[/b][br]
## [br]参数：[br]
## [param state_name] : 目标状态名[br]
## [param data] : 传递给 on_enter 的数据
func change_state(state_name: String, data := {}) -> void:
	if not _states.has(state_name):
		push_error("StateMachineHelper: 找不到状态 [%s]" % state_name)
		return

	# 退出旧状态
	if not current_state.is_empty() and _states[current_state].exit.is_valid():
		_states[current_state].exit.call()

	# 进入新状态
	current_state = state_name
	if _states[state_name].enter.is_valid():
		_states[state_name].enter.call(data)

## [b]每帧更新[/b][br]
## 在外部 _process 里调用[br]
## [br]参数：[br]
## [param delta] : 帧间隔
func update(delta: float) -> void:
	if not current_state.is_empty() and _states[current_state].update.is_valid():
		_states[current_state].update.call(delta)

## [b]清理[/b][br]
## 切换场景或销毁时调用
func clear() -> void:
	if not current_state.is_empty() and _states[current_state].exit.is_valid():
		_states[current_state].exit.call()
	current_state = ""
	_states.clear()
#endregion
