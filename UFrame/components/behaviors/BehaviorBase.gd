extends Node

'''
用法：
	1. 新建脚本 extends BehaviorBase
	2. 覆写 on_update(delta) / on_enter() / on_exit()
	3. 把 Behavior 节点挂到实体下（和 StateMachine 平级，不是嵌套）
	4. Behavior 可以多个并存，enabled = true 的都会执行
'''
## 行为委托基类，可多个 Behavior 并存于同一实体，每个 enabled 的 Behavior 每帧执行 on_update()
class_name BehaviorBase

#region 变量
## [b]是否启用[/b][br]
## false 时 on_update() 不执行
@export var enabled: bool = true

## [b]所属实体[/b][br]
## 未设置时自动取父节点
@export var entity: Node = null
#endregion

#region 生命周期（子类覆写）
## [b]行为被启用时调用[/b][br]
## enabled 从 false 变为 true 时触发，_ready 时若 enabled=true 也会触发
func on_enter() -> void:
	pass

## [b]行为被禁用/销毁时调用[/b]
func on_exit() -> void:
	pass

## [b]每帧调用[/b][br]
## enabled=true 时执行[br][br]
## [param _delta] : 帧间隔
func on_update(_delta: float) -> void:
	pass
#endregion

#region 生命周期
func _ready() -> void:
	# 自动找 entity（Behavior 的父节点就是实体）
	if not entity:
		entity = get_parent()
	
	# 如果一开始就是 enabled，触发 on_enter
	if enabled:
		on_enter()

func _process(delta: float) -> void:
	if enabled:
		on_update(delta)

func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		on_exit()
#endregion
