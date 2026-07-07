# ============================================================
# State.gd  —  状态基类（挂载版）
# 用法：
#   1. 新建一个 State 的 .gd 脚本，extends "res://UcatFrameWork/state_machine/State.gd"
#   2. 覆写以下方法（都是可选的）：
#      func on_enter(_data := {}) -> void:
#      func on_exit() -> void:
#      func on_update(_delta: float) -> void:
# ============================================================

class_name State
extends Node

## 当前状态名（自动取文件名，也可以在 Inspector 里改）
@export var state_name: String = ""

#region 内部引用（由 StateMachine 自动设置，子类不要手动改）

## 状态机引用
var state_machine: Node = null

## 所属实体（state_machine 的父节点，通常是敌人/玩家节点）
var entity: Node = null

#endregion

#region 生命周期（子类覆写这些，不是 _ready / _process）

## 进入状态时调用（只执行一次）
func on_enter(_data := {}) -> void:
	pass

## 离开状态时调用（只执行一次）
func on_exit() -> void:
	pass

## 每帧调用（替代 _process）
func on_update(_delta: float) -> void:
	pass

#endregion

#region 内部方法（子类一般不需要覆写）

func _enter_tree() -> void:
	# 如果没手动填 state_name，自动用文件名
	if state_name.is_empty():
		state_name = get_script().resource_path.get_file().get_basename()

func _ready() -> void:
	# 确保自己是 StateMachine 的子节点
	if not get_parent() is StateMachine:
		push_warning("State [%s] 必须挂载在 StateMachine 下" % state_name)

func _process(delta: float) -> void:
	# 只有当前激活的状态才执行更新
	if state_machine and state_machine.current_state == self:
		on_update(delta)

#endregion
