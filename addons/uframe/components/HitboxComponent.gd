extends Area2D

## 攻击判定框组件
##
## 挂到武器、子弹等攻击 [Area2D] 上，并添加 [CollisionShape2D] 子节点[br]
## 本组件只描述如何造成伤害；[UFrameHurtbox2D] 负责碰撞检测与生命结算[br]
## 自身不监听碰撞信号，避免双方同时结算造成重复伤害
class_name UFrameHitbox2D

#region 信号
## [b]命中确认[/b][br]
## 目标实际扣除生命后发出[br][br]
## [param target] : 受到命中的节点[br]
## [param applied_damage] : 实际造成的伤害
signal hit_confirmed(target: Node, applied_damage: int)
#endregion

#region 配置
## [b]基础伤害[/b]
@export var damage := 10

## [b]命中后销毁来源[/b][br]
## 成功命中后销毁父节点，常用于一次性子弹
@export var destroy_on_hit := false

## [b]单次激活只命中一次[/b][br]
## 启用后，同一个 [UFrameHurtbox2D] 在重置前只能被命中一次
@export var hit_once_per_activation := true
#endregion

#region 运行时状态
## [b]伤害来源[/b][br]
## 未手动设置时在初始化阶段使用父节点
var source: Node

## [b]已命中目标[/b][br][br]
## [color=cyan]集合：[/color]本次激活已经成功命中的 [UFrameHurtbox2D]。
var _hit_targets: Dictionary = {}
#endregion

#region 生命周期
func _ready() -> void:
	if source == null:
		source = get_parent()

## [b]对象池取出钩子[/b][br]
## [UFramePool] 取出实例时自动调用
func _on_pool_acquire() -> void:
	reset_hits()
#endregion

#region 主要方法
## [b]记录成功命中[/b][br]
## 仅应在目标确认伤害生效后调用[br][br]
## [param target] : 受到命中的节点[br]
## [param applied_damage] : 实际造成的伤害
func mark_hit(target: Node, applied_damage := damage) -> void:
	_hit_targets[target] = true
	hit_confirmed.emit(target, applied_damage)
	if destroy_on_hit and is_instance_valid(get_parent()):
		get_parent().queue_free()

## [b]重置命中记录[/b][br]
## 开始新的攻击窗口时调用
func reset_hits() -> void:
	_hit_targets.clear()
#endregion

#region 查询方法
## [b]判断是否可以命中[/b][br]
## 目标无效或已经在本次激活中命中过时返回 [code]false[/code][br][br]
## [param target] : 需要检查的目标节点
func can_hit(target: Node) -> bool:
	return is_instance_valid(target) and (not hit_once_per_activation or not _hit_targets.has(target))
#endregion
