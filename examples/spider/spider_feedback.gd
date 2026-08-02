class_name SpiderFeedbackOverlay
extends Control

## 蜘蛛纸牌的集中式轻量反馈层。
##
## 粒子、圆环和蛛丝轨迹都保存在小型数组中，只在存在效果时开启 _process()。
## 卡牌本身无需常驻逐帧更新。

const EFFECT_STEP := 1.0 / 30.0
const MAX_PARTICLES := 32
const MAX_RINGS := 3
const MAX_THREADS := 3

var _particles: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _threads: Array[Dictionary] = []
var _effect_accumulator := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

## 在局部坐标生成一次方向性碎光。
func burst(origin: Vector2, color: Color, amount := 14, inherited_velocity := Vector2.ZERO) -> void:
	var resolved_amount := mini(maxi(amount, 1), maxi(MAX_PARTICLES - _particles.size(), 0))
	for index in resolved_amount:
		var angle := TAU * float(index) / float(maxi(resolved_amount, 1)) + randf_range(-0.18, 0.18)
		var speed := randf_range(58.0, 155.0)
		_particles.append({
			"position": origin,
			"velocity": Vector2.from_angle(angle) * speed + inherited_velocity,
			"color": color,
			"age": 0.0,
			"lifetime": randf_range(0.32, 0.62),
			"size": randf_range(1.6, 3.8),
		})
	if _rings.size() < MAX_RINGS:
		_rings.append({
			"position": origin,
			"color": color,
			"age": 0.0,
			"lifetime": 0.34,
		})
	set_process(true)
	queue_redraw()

## 绘制一条短暂的蛛丝吸附轨迹。
func thread_snap(from: Vector2, to: Vector2, color: Color) -> void:
	if _threads.size() >= MAX_THREADS:
		return
	_threads.append({
		"from": from,
		"to": to,
		"color": color,
		"age": 0.0,
		"lifetime": 0.28,
	})
	set_process(true)
	queue_redraw()

## 完成 K-A 时组合蛛丝、圆环和更密集的碎光。
func completion_burst(from: Vector2, to: Vector2) -> void:
	thread_snap(from, to, Color("#74f0c1"))
	burst(to, Color("#ffc857"), 24, Vector2.UP * 24.0)

func _process(delta: float) -> void:
	# 反馈是很短的装饰动画，30 Hz 已足够顺滑；限制更新频率可将 Dictionary
	# 运算和自定义几何重建减半，同时不会影响卡牌本身的 60 Hz 变换动画。
	_effect_accumulator += delta
	if _effect_accumulator < EFFECT_STEP:
		return
	var effect_delta := minf(_effect_accumulator, EFFECT_STEP * 2.0)
	_effect_accumulator = 0.0
	for particle in _particles:
		particle.age += effect_delta
		particle.velocity += Vector2(0, 155.0) * effect_delta
		particle.position += particle.velocity * effect_delta
	for ring in _rings:
		ring.age += effect_delta
	for thread in _threads:
		thread.age += effect_delta
	# 反向原地清理，避免效果活跃时每帧由 filter() 额外分配三个新数组和闭包。
	for index in range(_particles.size() - 1, -1, -1):
		if _particles[index].age >= _particles[index].lifetime:
			_particles.remove_at(index)
	for index in range(_rings.size() - 1, -1, -1):
		if _rings[index].age >= _rings[index].lifetime:
			_rings.remove_at(index)
	for index in range(_threads.size() - 1, -1, -1):
		if _threads[index].age >= _threads[index].lifetime:
			_threads.remove_at(index)
	queue_redraw()
	if _particles.is_empty() and _rings.is_empty() and _threads.is_empty():
		_effect_accumulator = 0.0
		set_process(false)

func _draw() -> void:
	for thread in _threads:
		var ratio: float = thread.age / thread.lifetime
		var alpha := 1.0 - ratio
		var from: Vector2 = thread.from
		var to: Vector2 = thread.to
		var middle := (from + to) * 0.5 + Vector2(0, -34.0 * sin(ratio * PI))
		draw_polyline(PackedVector2Array([from, middle, to]), Color(thread.color, alpha), 2.0)
		for knot in 4:
			var t := float(knot + 1) / 5.0
			var point := from.lerp(middle, minf(t * 2.0, 1.0)) if t <= 0.5 else middle.lerp(to, (t - 0.5) * 2.0)
			draw_circle(point, 1.7, Color(thread.color, alpha * 0.82))
	for ring in _rings:
		var ratio: float = ring.age / ring.lifetime
		draw_arc(ring.position, 8.0 + ratio * 44.0, 0.0, TAU, 22, Color(ring.color, (1.0 - ratio) * 0.72), 2.0)
	for index in _particles.size():
		var particle := _particles[index]
		var ratio: float = particle.age / particle.lifetime
		var alpha := 1.0 - ratio
		var point: Vector2 = particle.position
		var radius: float = particle.size * (0.65 + alpha * 0.35)
		draw_circle(point, radius, Color(particle.color, alpha))
		# 一半粒子带拖尾即可形成方向感，减少短时峰值中的绘制命令。
		if index % 2 == 0:
			draw_line(point, point - particle.velocity.normalized() * radius * 2.8, Color(particle.color, alpha * 0.42), 1.0)
