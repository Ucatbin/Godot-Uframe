extends Node

## 状态机状态基类。
## 
## 必须作为 StateMachine 直属节点[br]
## 新建脚本继承 UFrameState，只覆写当前状态需要的回调
class_name UFrameState

#region 配置
## [b]当前状态名[/b][br][br]
## 未设置则自动使用节点名
@export var state_name: StringName
#endregion

#region 运行时状态
## [b]状态机引用[/b][br][br]
## 由 StateMachine 自动注入，无需手动修改
var state_machine: Node = null

## [b]所属实体[/b][br][br]
## StateMachine 的父节点，通常是敌人/玩家节点[br]
## 由 StateMachine 自动注入，无需手动修改
var entity: Node = null
#endregion

#region 生命周期
## [b]状态进入时调用[/b][br][br]
## [param _data] : 状态切换时传入的数据
func on_enter(_data := {}) -> void:
	pass

## [b]状态离开时调用[/b]
func on_exit() -> void:
	pass

## [b]普通帧更新[/b][br]
## 用于非物理逻辑[br][br]
## [param _delta] : 帧间隔
func on_update(_delta: float) -> void:
	pass

## [b]物理帧更新[/b][br]
## 用于物理逻辑[br][br]
## [param _delta] : 帧间隔
func on_physics_update(_delta: float) -> void:
	pass

func _enter_tree() -> void:
	# 如果没手动填写，使用节点名
	if state_name.is_empty():
		state_name = StringName(name)

func _ready() -> void:
	if not get_parent() is UFrameStateMachine:
		push_warning("[State] %s 必须挂载在 StateMachine 下" % state_name)
	# 状态由 StateMachine 统一驱动，避免子类误用 Godot 回调造成重复更新。
	set_process(false)
	set_physics_process(false)
#endregion
