class_name UFrameState
extends Node

## 节点式状态基类
##
## 必须作为 [UFrameStateMachine] 的直属子节点使用[br]
## 具体状态继承本类后，只需覆写当前状态需要的回调

#region 配置
## 状态名，留空时会在进入场景树时自动使用节点名
@export var state_name: StringName
#endregion

#region 运行时状态
## 状态机引用[br]
## 由 [UFrameStateMachine] 自动注入
var state_machine: Node = null

## 所属实体[br]
## 状态机的父节点，通常是玩家或敌人实体；由 [UFrameStateMachine] 自动注入
var entity: Node = null

## 是否已经完成一次性装配
var _is_setup := false
#endregion

#region 装配
## 注入状态机与实体，并执行一次性装配回调[br]
##
## 仅由 [UFrameStateMachine] 在收集完全部状态后调用；重复调用不会再次装配
func setup(new_state_machine: Node, new_entity: Node) -> void:
	if _is_setup:
		return
	state_machine = new_state_machine
	entity = new_entity
	_is_setup = true
	on_setup()
#endregion

#region 可覆写回调
## 状态机与实体注入完成后调用一次
func on_setup() -> void:
	pass

## 进入状态[br][br]
## [param _data] : 状态切换时传入的数据
func on_enter(_data := {}) -> void:
	pass

## 离开状态
func on_exit() -> void:
	pass

## 更新普通帧[br]
## 仅在本状态激活时由状态机转发[br][br]
## [param _delta] : 帧间隔
func on_update(_delta: float) -> void:
	pass

## 更新物理帧[br]
## 仅在本状态激活时由状态机转发[br][br]
## [param _delta] : 帧间隔
func on_physics_update(_delta: float) -> void:
	pass
#endregion

#region 生命周期
func _enter_tree() -> void:
	# 如果没手动填写，使用节点名
	if state_name.is_empty():
		state_name = StringName(name)

func _ready() -> void:
	if not get_parent() is UFrameStateMachine:
		push_warning("[State] %s 必须挂载在 StateMachine 下" % state_name)
	set_process(false)
	set_physics_process(false)
#endregion
