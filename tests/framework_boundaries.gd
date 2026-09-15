extends Node

## 框架边界回归，供 test_runner 调用。
## 覆盖缓存隔离、同步重入、批量事务、连续帧和音频请求；不负责性能计时。

class RedirectState extends UFrameState:
	var target: StringName
	var deferred := false
	var exits := 0

	func on_enter(_data: Dictionary = {}) -> void:
		if target.is_empty():
			return
		if deferred:
			state_machine.change_state.call_deferred(target)
		else:
			state_machine.change_state(target)

	func on_exit() -> void:
		exits += 1

#region 运行时状态
var _failures := 0
#endregion

#region 测试入口
## 返回失败数量，由综合入口决定退出码。
func run() -> int:
	_test_event_snapshots()
	_test_stats_cache()
	_test_inventory_batch()
	_test_health_notifications()
	_test_input_lifecycle()
	_test_camera_binding()
	_test_loot_batch_consumer()
	await _test_state_reentry()
	await _test_audio_requests()
	return _failures
#endregion

#region 同步数据与生命周期
func _test_event_snapshots() -> void:
	var bus := UFrameEventBus.new()
	var nested := [false]
	var calls := [0]
	bus.subscribe(&"nested", func() -> void:
		if not nested[0]:
			nested[0] = true
			bus.publish(&"nested")
	)
	bus.subscribe(&"nested", func() -> void: calls[0] += 1, true)
	bus.publish(&"nested")
	_expect(calls[0] == 1, "嵌套发布不能重复消费后续 once 订阅")
	var values: Array[int] = []
	var late := func() -> void: values.append(2)
	bus.subscribe(&"replace", func() -> void:
		values.append(1)
		bus.unsubscribe(&"replace", late)
		bus.subscribe(&"replace", late)
	, true)
	bus.subscribe(&"replace", late)
	bus.publish(&"replace")
	_expect(values == [1], "取消并重订阅不能复活旧快照中的记录")
	bus.publish(&"replace")
	_expect(values == [1, 2], "新订阅应在下次发布生效")
	bus.subscribe(&"clear", func() -> void: bus.clear())
	bus.subscribe(&"clear", func() -> void: values.append(3))
	bus.publish(&"clear")
	_expect(values == [1, 2], "clear 应立即使快照剩余订阅失效")
	bus.free()

func _test_stats_cache() -> void:
	var stats := UFrameStats.new()
	_expect(stats.get_stat("missing", 10.0) == 10.0, "缺少配置时使用本次默认值")
	_expect(stats.get_stat("missing", 20.0) == 20.0, "默认值不能被前次缓存覆盖")
	var mod := UFrameStatModifier.new()
	mod.stat_name = "missing"
	mod.value = 2.0
	stats.add_modifier(mod)
	_expect(stats.get_stat("missing", 20.0) == 22.0, "无基础配置的修正不能缓存通知阶段的零默认值")
	var source := {"speed": 10.0}
	stats.base_stats = source
	stats.get_stat("speed")
	source["speed"] = 99.0
	_expect(stats.get_stat("speed") == 10.0, "外部配置字典不能绕过属性修改入口")
	_expect(stats.base_stats.is_read_only(), "导出配置的查询快照不可直接修改")
	stats.set_base_stat("speed", 20.0)
	_expect(stats.get_stat("speed") == 20.0, "单项修改会使缓存失效")
	stats.base_stats = {"speed": 30.0}
	_expect(stats.get_stat("speed") == 30.0, "整体替换也会使缓存失效")
	var packed := PackedScene.new()
	stats.name = "Stats"
	_expect(packed.pack(stats) == OK, "Stats 的导出属性仍可场景序列化")
	var restored := packed.instantiate() as UFrameStats
	_expect(restored.get_stat("speed") == 30.0, "场景实例正确恢复基础值配置")
	restored.free()
	stats.free()

func _test_inventory_batch() -> void:
	var batch := UFrameInventory.new()
	var individual := UFrameInventory.new()
	for inventory: UFrameInventory in [batch, individual]:
		inventory.slot_count = 4
		inventory.max_stack_size = 4
		inventory.set_slots([{"item_id": &"a", "count": 3}, {}, {"item_id": &"b", "count": 2}, {}])
	var changed: Array[int] = []
	var commits := [0]
	batch.slot_changed.connect(func(index: int) -> void: changed.append(index))
	batch.inventory_changed.connect(func() -> void: commits[0] += 1)
	var requested: Dictionary[StringName, int] = {&"a": 3, &"b": 5, &"c": 3, &"": 2, &"d": -1}
	var actual := batch.add_items(requested)
	var expected: Dictionary[StringName, int] = {}
	for id: StringName in requested:
		var added := individual.add_item(id, requested[id])
		if added > 0:
			expected[id] = added
	_expect(actual == expected and batch.get_slots() == individual.get_slots(), "批量加入按请求顺序复用堆叠，并与逐项结果相同")
	var unique: Dictionary = {}
	for index in changed:
		unique[index] = true
	_expect(unique.size() == changed.size() and commits[0] == 1, "批量操作每格通知一次、整体通知一次")
	batch.sort_and_merge()
	changed.clear()
	commits[0] = 0
	batch.sort_and_merge()
	_expect(changed.is_empty() and commits[0] == 0, "已经整理好的背包不重复发送变化通知")
	batch.add_items({&"": 1, &"a": 0})
	_expect(commits[0] == 0, "无效批量请求不产生通知")
	# 多轮不同堆叠和容量验证，覆盖空背包、满背包、不同物品请求顺序。
	var rng := RandomNumberGenerator.new()
	rng.seed = 915
	for iteration in 64:
		batch.clear()
		individual.clear()
		var limit := rng.randi_range(1, 16)
		batch.max_stack_size = limit
		individual.max_stack_size = limit
		requested.clear()
		for id: StringName in [&"a", &"b", &"c"]:
			var initial := rng.randi_range(0, 6)
			batch.add_item(id, initial)
			individual.add_item(id, initial)
			requested[id] = rng.randi_range(0, 20)
		batch.add_items(requested)
		for id: StringName in requested:
			individual.add_item(id, requested[id])
		_expect(batch.get_slots() == individual.get_slots(), "批量与逐项加入的容量边界一致：%d" % iteration)
	batch.free()
	individual.free()

func _test_health_notifications() -> void:
	var health := UFrameHealth.new()
	add_child(health)
	var changes: Array = []
	health.hp_changed.connect(func(old: int, value: int) -> void: changes.append([old, value]))
	health.set_max_hp(200, true)
	health.set_max_hp(200, true)
	_expect(changes == [[100, 200]], "补满只在 HP 真正变化时通知")
	var stats := UFrameStats.new()
	stats.base_stats = {"max_hp": 50.0}
	health.set_stat_component(stats)
	_expect(health.hp == 50 and changes.back() == [200, 50], "切换属性依赖时限制 HP 并通知")
	health.set_stat_component(null, true)
	_expect(health.hp == 200 and changes.back() == [50, 200], "移除属性依赖时的补满同样通知")
	var hitbox := UFrameHitbox2D.new()
	hitbox.hit_once_per_activation = false
	hitbox.mark_hit(health, 1)
	_expect((hitbox.get("_hit_targets") as Dictionary).is_empty(), "不限次攻击不保存无用命中记录")
	hitbox.free()
	health.free()
	stats.free()

func _test_input_lifecycle() -> void:
	var service := UFrameInput.new()
	service.buffer_action("jump", 0.05)
	add_child(service)
	_expect(service.is_processing(), "入树前的输入缓冲继续计时")
	service._process(0.06)
	_expect(not service.is_action_buffered("jump") and not service.is_processing(), "最后一个缓冲过期后停止处理")
	service.buffer_action("jump")
	service.consume_buffer("jump")
	_expect(not service.is_processing(), "消耗最后一项时立即停止处理")
	service.buffer_action("jump")
	service.clear_all_buffers()
	_expect(not service.is_processing(), "清空时立即停止处理")
	service.free()

func _test_camera_binding() -> void:
	var camera := Camera2D.new()
	var service := UFrameCamera2D.new()
	add_child(camera)
	add_child(service)
	camera.offset = Vector2(3, 5)
	service.set_camera(camera)
	service.add_trauma(1.0)
	service._process(0.016)
	service.set_camera(camera)
	service.clear_trauma()
	_expect(camera.offset == Vector2(3, 5), "震动中重复绑定不能污染基准变换")
	service.free()
	camera.free()
#endregion

#region 连续帧与异步请求
func _test_loot_batch_consumer() -> void:
	var scene := load("res://examples/loot/loot_demo.tscn") as PackedScene
	var demo := scene.instantiate()
	add_child(demo)
	# 使用独立配置保证本轮有掉落，不修改示例共享 Resource。
	demo.loot_table = demo.loot_table.duplicate()
	demo.loot_table.no_drop_weight = 0.0
	var commits := [0]
	demo.inventory.inventory_changed.connect(func() -> void: commits[0] += 1)
	demo._roll_batch()
	_expect(demo.roll_count == 10 and commits[0] == 1, "十连示例一次提交所有合并掉落")
	demo.free()

func _test_state_reentry() -> void:
	var entity := Node.new()
	var machine := UFrameStateMachine.new()
	var a := RedirectState.new()
	a.name = "A"
	a.target = &"B"
	var b := RedirectState.new()
	b.name = "B"
	machine.initial_state = &"A"
	machine.add_child(a)
	machine.add_child(b)
	entity.add_child(machine)
	var changes: Array = []
	machine.state_changed.connect(func(previous: StringName, current: StringName) -> void:
		changes.append([previous, current, machine.get_current_state_name()])
	)
	add_child(entity)
	_expect(changes == [[&"", &"A", &"A"]], "同步重入被拒绝，通知与实际状态保持一致")
	machine.change_state(&"B")
	a.deferred = true
	machine.change_state(&"A")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(machine.is_in_state(&"B") and a.exits == 2, "延迟切换正常完成，并保持退出次数正确")
	for change: Array in changes:
		_expect(change[1] == change[2], "每次通知时当前状态都与通知一致")
	entity.free()

func _test_audio_requests() -> void:
	var service := UFrameAudio.new()
	add_child(service)
	var stream_a := AudioStreamWAV.new()
	stream_a.format = AudioStreamWAV.FORMAT_8_BITS
	stream_a.mix_rate = 8000
	stream_a.data = PackedByteArray([128, 128, 128, 128, 128, 128, 128, 128])
	stream_a.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream_a.loop_end = 8
	var stream_b := stream_a.duplicate() as AudioStreamWAV
	service.play_bgm(stream_a, 0.0)
	service.play_bgm(stream_b, 0.08)
	service.master_volume = 0.5
	service.muted = true
	await get_tree().create_timer(0.18).timeout
	var player := service.get("_bgm_player") as AudioStreamPlayer
	_expect(player.stream == stream_b and player.volume_db <= -79.0, "静音和音量设置不取消淡出阶段的切歌")
	service.muted = false
	_expect(is_equal_approx(player.volume_db, linear_to_db(0.5)), "淡入结束后使用当前用户音量")
	service.stop_bgm(0.05)
	service.bgm_volume = 0.8
	await get_tree().create_timer(0.12).timeout
	_expect(player.stream == null and not player.playing, "调节音量不取消停止音乐请求")
	service.play_bgm(stream_a, 0.05)
	service.play_bgm(stream_b, 0.05)
	service.play_bgm(stream_a, 0.05)
	await get_tree().create_timer(0.15).timeout
	_expect(player.stream == stream_a, "连续播放请求只执行最新切歌")
	service.free()
	await get_tree().create_timer(0.05).timeout
#endregion

#region 结果检查
func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("[UFrameBoundaryTest] %s" % message)
#endregion
