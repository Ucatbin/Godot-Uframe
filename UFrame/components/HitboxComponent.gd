extends Area2D

'''
描述：
	攻击碰撞框组件
	挂载到武器/子弹节点上，检测到对方 HurtboxComponent 时自动造成伤害

用法：
	1. 把 HitboxComponent 挂到有 CollisionShape2D 的子节点上
	2. 设置 damage 和 source（来源实体）
	3. 检测到碰撞时自动调用对方 HealthComponent.take_damage()
'''

class_name HitboxComponent

#region 变量
## [b]伤害值[/b]
@export var damage: int = 10

## [b]伤害来源[/b][br]
## 通常是玩家/敌人节点，未设置时自动取父节点
var source: Node = null

## [b]命中后自动销毁[/b][br]
## 子弹/飞行道具通常设为 true
@export var destroy_on_hit: bool = false

## [b]已命中的实体列表[/b][br]
## 防止同一帧内对同一目标重复造成伤害
var _hit_entities: Array = []
#endregion

#region 生命周期
func _ready() -> void:
	# 自动找 source（挂在谁下面就是谁的攻击）
	if not source:
		source = get_parent()

	# 连接碰撞信号
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _enter_tree() -> void:
	# 每帧清空命中记录（允许下一帧再次伤害）
	get_tree().process_frame.connect(_clear_hit_entities, CONNECT_ONE_SHOT)
#endregion

#region 碰撞处理
func _on_body_entered(body: Node) -> void:
	_try_hit(body)

func _on_area_entered(area: Area2D) -> void:
	_try_hit(area)

## [b]尝试对目标造成伤害[/b][br]
## [br]参数：[br]
## [param target] : 被命中的节点
func _try_hit(target: Node) -> void:
	if not target or target in _hit_entities:
		return

	# 查找对方的 HealthComponent
	var health_comp = target.get_node_or_null("HealthComponent")
	if not health_comp:
		# 也可能 HealthComponent 在父节点上
		if target.get_parent().has_node("HealthComponent"):
			health_comp = target.get_parent().get_node("HealthComponent")

	if health_comp and health_comp.has_method("take_damage"):
		health_comp.take_damage(damage, source)
		_hit_entities.append(target)

		EventBus.send("hit_landed", {
			"source": source,
			"target": target,
			"damage": damage
		})

		if destroy_on_hit:
			get_parent().queue_free()
#endregion

#region 内部方法
## [b]清空本帧命中记录[/b]
func _clear_hit_entities() -> void:
	_hit_entities.clear()
	# 下一帧继续注册
	if is_inside_tree():
		get_tree().process_frame.connect(_clear_hit_entities, CONNECT_ONE_SHOT)
#endregion
