extends Node

## 可复用实体生命组件。
##
## 负责生命值、伤害、治疗、受伤无敌与死亡通知，可通过 [member stat_component_path] 读取 [UFrameStats]。
## 不负责碰撞检测、阵营过滤或受伤视觉，这些职责分别属于 Hurtbox、Team 与实体表现脚本。
## 打开 [code]examples/arena/arena_player.tscn[/code] 可查看本组件与战斗组件的场景组合。
class_name UFrameHealth

#region 信号
## 生命值发生变化。
## [param old_value] 是变化前生命值，[param new_value] 是变化后生命值。
signal hp_changed(old_value: int, new_value: int)

## 伤害实际生效。
## [param amount] 是实际扣除量，不会超过受击前剩余生命值；[param source] 是伤害来源节点。
signal damaged(amount: int, source: Node)

## 治疗实际生效。[param amount] 是实际恢复量。
signal healed(amount: int)

## 生命值首次降到 [code]0[/code] 时发出。[param source] 是击杀来源节点。
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
## 请求承受伤害；无敌、死亡或非正数伤害不会生效。
## [param amount] 是请求伤害值，[param source] 是伤害来源；返回实际扣除量。
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

## 请求恢复 [param amount] 点生命；不会超过有效最大生命值，并返回实际恢复量。
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

## 清理无敌计时，适合对象池实体重新取出时调用。
## [param fill_to_max] 为 [code]true[/code] 时补满生命，否则只把当前值限制在合法范围。
func reset(fill_to_max: bool = true) -> void:
	var old_hp := hp
	_invincible_timer = 0.0
	set_process(false)
	hp = _get_effective_max_hp() if fill_to_max else clampi(hp, 0, _get_effective_max_hp())
	if hp != old_hp:
		hp_changed.emit(old_hp, hp)

## 补满至有效最大生命值并返回实际恢复量，适合回合重开或对象池实体复用。
func refill() -> int:
	var old_hp := hp
	hp = _get_effective_max_hp()
	var applied := hp - old_hp
	if hp != old_hp:
		hp_changed.emit(old_hp, hp)
	if applied > 0:
		healed.emit(applied)
	return maxi(applied, 0)

## 设置最大生命值。
## 绑定 [UFrameStats] 时修改其中 [code]max_hp[/code] 的基础值，否则修改本组件配置；[param fill] 决定是否补满。
func set_max_hp(v: int, fill: bool = true) -> void:
	v = maxi(v, 1)
	if _stat_component:
		_stat_component.set_base_stat("max_hp", float(v))
	else:
		max_hp = v
	if fill:
		hp = _get_effective_max_hp()
	else:
		var old_hp := hp
		hp = mini(hp, _get_effective_max_hp())
		if hp != old_hp:
			hp_changed.emit(old_hp, hp)

## 显式设置可选属性组件，适合纯代码创建的实体；传入 [code]null[/code] 可恢复独立运行。
## [param refill] 决定是否按新的有效最大值补满生命。
func set_stat_component(component: UFrameStats, refill: bool = false) -> void:
	_stat_component = component
	if refill:
		hp = _get_effective_max_hp()
#endregion

#region 状态查询
## 判断当前生命值是否已经归零。
func is_dead() -> bool:
	return hp <= 0

## 判断受伤无敌计时是否仍在生效。
func is_invincible() -> bool:
	return _invincible_timer > 0
#endregion

#region 属性读取
## 获取有效最大生命值；绑定 [UFrameStats] 时读取 [code]max_hp[/code]，否则使用 [member max_hp]。
func _get_effective_max_hp() -> int:
	if _stat_component:
		return int(_stat_component.get_stat("max_hp", float(max_hp)))
	return max_hp
#endregion
