extends Node

## 节点式互斥状态基类。
##
## 负责接收 [UFrameStateMachine] 与所属实体引用，并定义一次性装配和状态生命周期回调。
## 不自行切换状态或启用帧处理；当前状态的更新只由所属状态机转发。
## 打开 [code]examples/platformer/platformer_player.tscn[/code] 可查看 State 作为状态机直属子节点的组合。
class_name UFrameState

#region Inspector 配置
## 状态语义 ID；留空时在进入场景树时使用节点名。
@export var state_name: StringName
#endregion

#region 依赖引用
## 所属状态机，由 [UFrameStateMachine] 自动注入。
var state_machine: Node = null

## 所属实体，即状态机的父节点；由 [UFrameStateMachine] 自动注入。
var entity: Node = null
#endregion

#region 运行时状态
## 是否已经完成一次性装配。
var _is_setup := false
#endregion

#region 状态装配
## 注入状态机与实体，并执行一次 [method on_setup]。
## 仅由 [UFrameStateMachine] 在收集完全部状态后调用；重复调用不会再次装配。
func setup(new_state_machine: Node, new_entity: Node) -> void:
	if _is_setup:
		return
	state_machine = new_state_machine
	entity = new_entity
	_is_setup = true
	on_setup()
#endregion

#region 可覆写状态回调
## 状态机与实体完成注入后调用一次，适合缓存强类型依赖。
func on_setup() -> void:
	pass

## 每次进入本状态时调用；[param _data] 是状态切换方传入的数据字典。
func on_enter(_data: Dictionary = {}) -> void:
	pass

## 每次离开本状态时调用。
func on_exit() -> void:
	pass

## 本状态激活时由状态机转发普通帧更新。[param _delta] 是当前帧间隔。
func on_update(_delta: float) -> void:
	pass

## 本状态激活时由状态机转发物理帧更新。[param _delta] 是当前物理帧间隔。
func on_physics_update(_delta: float) -> void:
	pass
#endregion

#region 生命周期
## 为未显式填写的 [member state_name] 使用节点名。
func _enter_tree() -> void:
	if state_name.is_empty():
		state_name = StringName(name)

## 校验场景层级，并确保 State 本身不进入 Godot 帧循环。
func _ready() -> void:
	if not get_parent() is UFrameStateMachine:
		push_warning("[UFrameState] %s 必须挂载在 UFrameStateMachine 下" % state_name)
	set_process(false)
	set_physics_process(false)
#endregion
