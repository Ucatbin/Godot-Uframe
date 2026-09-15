extends Node

## 可复用实体生命组件。
##
## 负责生命值、伤害、治疗、受伤无敌与死亡通知，可通过 [member stat_component_path] 读取 [UFrameStats]。
## 不负责碰撞检测、阵营过滤或受伤视觉，这些职责分别属于 Hurtbox、Team 与实体表现脚本。
## 打开 [code]examples/arena/arena_player.tscn[/code] 可查看本组件与战斗组件的场景组合。
class_name UFrameHealth

#region 信号
## 生命值发生变化时发出。 [br][br]
## [param old_value] : 变化前的生命值 [br]
## [param new_value] : 变化后的生命值
signal hp_changed(old_value: int, new_value: int)

## 伤害实际生效时发出。 [br][br]
## [param amount] : 实际扣除量，不超过受击前剩余生命值 [br]
## [param source] : 伤害来源节点，可为 [code]null[/code]
signal damaged(amount: int, source: Node)

## 治疗实际生效时发出。 [br][br]
## [param amount] : 实际恢复的生命值
signal healed(amount: int)

## 生命值首次降到 [code]0[/code] 时发出。 [br][br]
## [param source] : 击杀来源节点，可为 [code]null[/code]
signal died(source: Node)
#endregion

#region Inspector 配置
## 独立运行时使用的最大生命值；绑定 [UFrameStats] 后改为读取其中 [code]max_hp[/code] 的最终值。
@export var max_hp: int = 100

## 可选的 [UFrameStats] 节点路径；留空时独立运行。
@export var stat_component_path: NodePath

## 每次伤害生效后的无敌时间，单位为秒；[code]0.0[/code] 表示不启用。
@export var invincible_duration: float = 0.0
#endregion

#region 依赖引用
## 由 [member stat_component_path] 解析的可选属性组件。
var _stat_component: UFrameStats = null
#endregion

#region 运行时状态
## 当前生命值。
var hp: int = 100

## 剩余无敌时间，归零后自动停止普通帧处理。
var _invincible_timer: float = 0.0
#endregion

#region 生命周期
## 解析可选属性组件，以有效最大生命初始化当前值，并保持帧处理关闭。
func _ready() -> void:
	if not stat_component_path.is_empty():
		_stat_component = get_node_or_null(stat_component_path) as UFrameStats
		if _stat_component == null:
			push_warning("[UFrameHealth] 找不到 UFrameStats：%s" % stat_component_path)

	hp = _get_effective_max_hp()
	set_process(false)

func _process(delta: float) -> void:
	if _invincible_timer > 0:
		_invincible_timer -= delta
		if _invincible_timer <= 0.0:
			_invincible_timer = 0.0
			set_process(false)
#endregion

#region 生命操作
## 请求承受伤害；无敌、死亡或非正数伤害不会生效。 [br]
## 返回实际扣除量。 [br][br]
## [param amount] : 请求伤害值 [br]
## [param source] : 伤害来源节点，可为 [code]null[/code]
func take_damage(amount: int, source: Node = null) -> int:
	if _invincible_timer > 0:
		return 0
	if amount <= 0:
		return 0
	if hp <= 0:
		return 0

	var old_hp := hp
	hp = maxi(hp - amount, 0)
	var applied := old_hp - hp
	hp_changed.emit(old_hp, hp)
	damaged.emit(applied, source)
	_invincible_timer = invincible_duration
	set_process(_invincible_timer > 0.0)

	if hp <= 0:
		died.emit(source)
	return applied

## 请求恢复 [param amount] 点生命；不会超过有效最大生命值，并返回实际恢复量。 [br][br]
## [param amount] : 请求恢复的生命值
func heal(amount: int) -> int:
	if amount <= 0:
		return 0
	var old := hp
	hp = clampi(hp + amount, 0, _get_effective_max_hp())
	var applied := hp - old
	if applied == 0:
		return 0
	hp_changed.emit(old, hp)
	healed.emit(applied)
	return applied

## 清理无敌计时，适合对象池实体重新取出时调用。 [br][br]
## [param fill_to_max] : 是否补满生命；否则只把当前值限制在合法范围
func reset(fill_to_max: bool = true) -> void:
	_invincible_timer = 0.0
	set_process(false)
	_sync_hp_to_maximum(fill_to_max)

## 补满至有效最大生命值并返回实际恢复量，适合回合重开或对象池实体复用。
func refill() -> int:
	var applied := _sync_hp_to_maximum(true)
	if applied > 0:
		healed.emit(applied)
	return maxi(applied, 0)

## 设置最大生命值。 [br]
## 绑定 [UFrameStats] 时修改其中 [code]max_hp[/code] 的基础值，否则修改本组件配置。 [br][br]
## [param v] : 新的最大生命值 [br]
## [param fill] : 是否补满生命
func set_max_hp(v: int, fill: bool = true) -> void:
	v = maxi(v, 1)
	if _stat_component:
		_stat_component.set_base_stat("max_hp", float(v))
	else:
		max_hp = v
	_sync_hp_to_maximum(fill)

## 显式设置可选属性组件，适合纯代码创建的实体。 [br]
## 当前生命值超过新上限时会被限制，并通知实际变化。 [br][br]
## [param component] : 可选属性组件；传入 [code]null[/code] 恢复独立运行 [br]
## [param refill] : 是否补满生命；为 [code]false[/code] 时仅限制当前值不超过新上限
func set_stat_component(component: UFrameStats, refill: bool = false) -> void:
	_stat_component = component
	_sync_hp_to_maximum(refill)
#endregion

#region 状态查询
## 判断当前生命值是否已经归零。
func is_dead() -> bool:
	return hp <= 0

## 判断受伤无敌计时是否仍在生效。
func is_invincible() -> bool:
	return _invincible_timer > 0
#endregion

#region 生命上限同步
## 补满、复位或更换上限后统一限制 HP，并只在实际变化时通知。 [br]
## 返回有符号变化量；降低上限不当作治疗或伤害。 [br][br]
## [param fill] : 是否补满生命
func _sync_hp_to_maximum(fill: bool) -> int:
	var old_hp := hp
	var maximum := _get_effective_max_hp()
	hp = maximum if fill else clampi(hp, 0, maximum)
	var delta := hp - old_hp
	if delta != 0:
		hp_changed.emit(old_hp, hp)
	return delta

## 获取有效最大生命值；绑定 [UFrameStats] 时读取 [code]max_hp[/code]，否则使用 [member max_hp]。
func _get_effective_max_hp() -> int:
	if _stat_component:
		return maxi(int(_stat_component.get_stat("max_hp", float(max_hp))), 1)
	return maxi(max_hp, 1)
#endregion
