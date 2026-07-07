# ============================================================
# BehaviorBase.gd  — 行为委托基类（挂载版）
# 用法：
#   1. 新建脚本 extends "res://UcatFrameWork/behaviors/BehaviorBase.gd"
#   2. 覆写 on_update(delta) / on_enter() / on_exit()
#   3. 把 Behavior 节点挂到实体下（和 StateMachine 平级，不是嵌套）
#   4. Behavior 可以多个并存，enabled = true 的都会执行
# ============================================================

class_name BehaviorBase
extends Node


#region 变量
## 是否启用（false 时 on_update 不执行）
@export var enabled: bool = true

## 所属实体
@export var entity: Node = null

#endregion

#region 生命周期（子类覆写）
## 行为被启用时调用（enabled 从 false 变 true）
func on_enter() -> void:
	pass

## 行为被禁用/销毁时调用
func on_exit() -> void:
	pass

## 每帧调用（替代 _process，只有 enabled=true 才执行）
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
