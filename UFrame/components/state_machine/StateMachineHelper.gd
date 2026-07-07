# ============================================================
# StateMachineHelper.gd  — 纯代码版状态机（不需要挂节点）
# 适合在 _process 里手动调用，或者在不能挂节点的地方用
#
# 用法：
#   var fsm = StateMachineHelper.new()
#   fsm.add_state("Idle", func(_d): pass, func(): pass, func(_d): pass)
#   fsm.add_state("Attack", ..., ..., ...)
#   fsm.change_state("Idle")
#
#   func _process(delta):
#       fsm.update(delta)
# ============================================================

class_name StateMachineHelper
extends RefCounted

## 当前状态名
var current_state: String = ""

# 存储所有状态：{ state_name: { enter, exit, update } }
var _states: Dictionary = {}

#region 核心 API

## 添加一个状态（enter/update/exit 都可以传 null）
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

## 切换状态
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

## 每帧更新（在外部 _process 里调用）
func update(delta: float) -> void:
	if not current_state.is_empty() and _states[current_state].update.is_valid():
		_states[current_state].update.call(delta)

## 清理（切换场景时调用）
func clear() -> void:
	if not current_state.is_empty() and _states[current_state].exit.is_valid():
		_states[current_state].exit.call()
	current_state = ""
	_states.clear()

#endregion
