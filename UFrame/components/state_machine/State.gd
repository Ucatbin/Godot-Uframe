extends Node

'''
描述：
	状态基类（StateMachine 挂载版）
	作为 StateMachine 的子节点，自动被识别为状态
用法：
	1. 新建脚本 extends State
	2. 覆写以下方法（可选）：
	   func on_enter(_data := {}) -> void:
	   func on_exit() -> void:
	   func on_update(_delta: float) -> void:
'''
## 
class_name State

#region 变量
## [b]当前状态名[/b][br]
## 自动取文件名，也可以在 Inspector 中修改
@export var state_name: String = ""

## [b]状态机引用[/b][br]
## 由 StateMachine 自动设置，子类不要手动修改
var state_machine: Node = null

## [b]所属实体[/b][br]
## state_machine 的父节点，通常是敌人/玩家节点[br]
## 由 StateMachine 自动设置，子类不要手动修改
var entity: Node = null
#endregion

#region 生命周期（子类覆写）
## [b]进入状态时调用[/b][br][br]
## [param _data] : 状态切换时传入的数据
func on_enter(_data := {}) -> void:
	pass

## [b]离开状态时调用[/b]
func on_exit() -> void:
	pass

## [b]逻辑更新[/b][br][br]
## [param _delta] : 帧间隔
func on_update(_delta: float) -> void:
	pass

## [b]物理更新[/b][br][br]
## [param _delta] : 帧间隔
func on_physics_update(_delta: float) -> void:
	pass
#endregion

#region 内部方法
func _enter_tree() -> void:
	# 如果没手动填 state_name，自动用文件名
	if state_name.is_empty():
		state_name = get_script().resource_path.get_file().get_basename()

func _ready() -> void:
	if not get_parent() is StateMachine:
		push_warning("State [%s] 必须挂载在 StateMachine 下" % state_name)
	set_process(false)
#endregion
