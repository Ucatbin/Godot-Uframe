extends Area2D

## 攻击判定框组件。
##
## 负责保存伤害来源、伤害值和单次激活的命中记录，并在伤害生效后发出确认信号。
## 不监听碰撞或直接修改生命值，避免 Hitbox 与 Hurtbox 两端重复结算。
## 实体监听 hit_confirmed 决定穿透、销毁或归还对象池，本组件不释放父节点。
## 打开 [code]examples/arena/arena_bullet.tscn[/code] 可查看本组件与碰撞形状的场景组合。
class_name UFrameHitbox2D

#region 信号
## 目标实际扣除生命后发出。 [br][br]
## [param target] : 受到命中的目标节点 [br]
## [param applied_damage] : 实际造成的伤害
signal hit_confirmed(target: Node, applied_damage: int)
#endregion

#region Inspector 配置
## 请求造成的基础伤害。
@export var damage := 10

## 是否限制同一个 [UFrameHurtbox2D] 在 [method reset_hits] 前只能命中一次。
@export var hit_once_per_activation := true
#endregion

#region 依赖引用
## 伤害来源；未显式注入时在 ready 阶段使用父节点。
var source: Node
#endregion

#region 运行时状态
## 本次激活已经成功命中的 [UFrameHurtbox2D] 集合。
var _hit_targets: Dictionary = {}
#endregion

#region 生命周期
## 为未显式配置的 [member source] 使用父节点。
func _ready() -> void:
	if source == null:
		source = get_parent()

## 当本组件是池化场景根节点时，由 [UFramePool] 取出实例时调用。 [br]
## 本组件作为子节点时，应由池化实体根转发此钩子或显式调用 [method reset_hits]。
func _on_pool_acquire() -> void:
	reset_hits()
#endregion

#region 命中生命周期
## 记录一次已经生效的命中并发出 [signal hit_confirmed]。 [br]
## 仅应由伤害结算方在目标实际扣血后调用。 [br][br]
## [param target] : 受到命中的目标节点 [br]
## [param applied_damage] : 实际造成的伤害
func mark_hit(target: Node, applied_damage: int = damage) -> void:
	if hit_once_per_activation:
		_hit_targets[target] = true
	hit_confirmed.emit(target, applied_damage)

## 清空本次激活的命中记录；开始新的攻击窗口或复用实例时调用。
func reset_hits() -> void:
	_hit_targets.clear()
#endregion

#region 命中查询
## 判断 [param target] 是否可以在本次激活中被命中。 [br]
## 目标无效，或启用单次限制且已经命中过时返回 [code]false[/code]。 [br][br]
## [param target] : 受到命中的目标节点
func can_hit(target: Node) -> bool:
	return is_instance_valid(target) and (not hit_once_per_activation or not _hit_targets.has(target))
#endregion
