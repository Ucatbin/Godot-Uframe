extends Node

## UFrame 的独立极限性能基准入口。
##
## 覆盖 EventBus、Registry、Inventory、Stats、StateMachine、Input 与 Pool 的常见
## 高负载路径。结果只记录工作量、耗时和吞吐，不使用与硬件绑定的毫秒阈值。
## 普通正确性回归仍由 tests/test_runner.tscn 负责，本场景不会被其自动执行。

class PerformanceState extends UFrameState:
	var enter_count := 0
	var exit_count := 0
	var update_count := 0
	var physics_update_count := 0

	func on_enter(_data: Dictionary = {}) -> void:
		enter_count += 1

	func on_exit() -> void:
		exit_count += 1

	func on_update(_delta: float) -> void:
		update_count += 1

	func on_physics_update(_delta: float) -> void:
		physics_update_count += 1

	func reset_counts() -> void:
		enter_count = 0
		exit_count = 0
		update_count = 0
		physics_update_count = 0

class PerformanceEventSink extends RefCounted:
	var weight := 0
	var checksum := 0

	func receive(value: Variant) -> void:
		checksum += int(value) + weight

class PerformanceEventNode extends Node:
	func receive(_value: Variant) -> void:
		pass

#region 基准配置
const POOL_ITEM_SCENE := preload("res://tests/performance/performance_pool_item.tscn")

## 三档负载只改变工作量，不改变被测路径。
const PROFILES := {
	"quick": {
		"event_subscribers": 8,
		"event_publishes": 2000,
		"event_empty_publishes": 50000,
		"event_invalid_subscribers": 128,
		"registry_entries": 5000,
		"registry_queries": 100000,
		"inventory_items": 256,
		"inventory_queries": 100000,
		"inventory_sorts": 10,
		"stat_modifiers": 128,
		"stat_individual_modifiers": 64,
		"stat_queries": 100000,
		"stat_dirty_updates": 64,
		"state_transitions": 20000,
		"state_dispatches": 50000,
		"input_actions": 256,
		"input_frames": 30,
		"input_queries": 50000,
		"pool_capacity": 64,
		"pool_batch": 64,
		"pool_cycles": 40,
		"pool_overflow_acquires": 1000,
	},
	"standard": {
		"event_subscribers": 64,
		"event_publishes": 10000,
		"event_empty_publishes": 500000,
		"event_invalid_subscribers": 1000,
		"registry_entries": 25000,
		"registry_queries": 1000000,
		"inventory_items": 1024,
		"inventory_queries": 1000000,
		"inventory_sorts": 50,
		"stat_modifiers": 512,
		"stat_individual_modifiers": 128,
		"stat_queries": 1000000,
		"stat_dirty_updates": 250,
		"state_transitions": 250000,
		"state_dispatches": 500000,
		"input_actions": 2048,
		"input_frames": 60,
		"input_queries": 500000,
		"pool_capacity": 512,
		"pool_batch": 256,
		"pool_cycles": 200,
		"pool_overflow_acquires": 5000,
	},
	"stress": {
		"event_subscribers": 256,
		"event_publishes": 25000,
		"event_empty_publishes": 2000000,
		"event_invalid_subscribers": 5000,
		"registry_entries": 100000,
		"registry_queries": 5000000,
		"inventory_items": 1024,
		"inventory_queries": 5000000,
		"inventory_sorts": 250,
		"stat_modifiers": 2000,
		"stat_individual_modifiers": 256,
		"stat_queries": 5000000,
		"stat_dirty_updates": 1000,
		"state_transitions": 1000000,
		"state_dispatches": 2000000,
		"input_actions": 10000,
		"input_frames": 120,
		"input_queries": 2000000,
		"pool_capacity": 2048,
		"pool_batch": 1024,
		"pool_cycles": 500,
		"pool_overflow_acquires": 20000,
	},
}

const SCENARIO_NAMES: Array[StringName] = [
	&"event_bus",
	&"registry",
	&"inventory",
	&"stats",
	&"state_machine",
	&"input",
	&"pool",
]
#endregion

#region 运行时状态
var _profile_name := "standard"
var _scale: Dictionary = {}
var _selected_scenarios: Dictionary[StringName, bool] = {}
var _failure_count := 0
var _result_count := 0
#endregion

#region 生命周期
## 解析命令行、依次执行选中的基准，并以退出码表达正确性检查结果。
func _ready() -> void:
	_parse_arguments()
	if not PROFILES.has(_profile_name):
		push_error("[UFramePerformance] 未知负载档位：%s" % _profile_name)
		get_tree().quit(2)
		return
	_scale = PROFILES[_profile_name]
	var total_started_at := Time.get_ticks_usec()
	_print_environment()
	if _should_run(&"event_bus"):
		_benchmark_event_bus()
	if _should_run(&"registry"):
		_benchmark_registry()
	if _should_run(&"inventory"):
		_benchmark_inventory()
	if _should_run(&"stats"):
		_benchmark_stats()
	if _should_run(&"state_machine"):
		await _benchmark_state_machine()
	if _should_run(&"input"):
		await _benchmark_input()
	if _should_run(&"pool"):
		await _benchmark_pool()
	# 等待 queue_free 和测试节点退出，避免把清理工作留给进程关闭阶段。
	await get_tree().process_frame
	await get_tree().process_frame
	var summary := {
		"profile": _profile_name,
		"results": _result_count,
		"failures": _failure_count,
		"elapsed_usec": Time.get_ticks_usec() - total_started_at,
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"static_memory_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
	}
	print("UFRAME_PERF_SUMMARY %s" % JSON.stringify(summary))
	if _failure_count == 0:
		print("UFRAME_PERF_OK")
		get_tree().quit(0)
	else:
		push_error("[UFramePerformance] 正确性检查失败：%d" % _failure_count)
		get_tree().quit(1)
#endregion

#region EventBus 基准
## 分别测量订阅建立、有订阅发布和空事件发布，避免把不同复杂度混成一个数字。
func _benchmark_event_bus() -> void:
	var subscriber_count := int(_scale.event_subscribers)
	var publish_count := int(_scale.event_publishes)
	var empty_publish_count := int(_scale.event_empty_publishes)
	var invalid_subscriber_count := int(_scale.event_invalid_subscribers)
	var bus := UFrameEventBus.new()
	var sinks: Array[PerformanceEventSink] = []
	var callbacks: Array[Callable] = []
	sinks.resize(subscriber_count)
	callbacks.resize(subscriber_count)
	for index in subscriber_count:
		var sink := PerformanceEventSink.new()
		sink.weight = index
		sinks[index] = sink
		callbacks[index] = sink.receive

	var started_at := Time.get_ticks_usec()
	for callback in callbacks:
		bus.subscribe(&"performance:event", callback)
	_record_result(
		"event_bus_subscribe",
		subscriber_count,
		Time.get_ticks_usec() - started_at,
		{"subscribers": subscriber_count}
	)

	started_at = Time.get_ticks_usec()
	for _index in publish_count:
		bus.publish(&"performance:event", 1)
	var publish_elapsed := Time.get_ticks_usec() - started_at
	var event_checksum := 0
	for sink in sinks:
		event_checksum += sink.checksum
	var expected_per_publish: int = subscriber_count + subscriber_count * (subscriber_count - 1) / 2
	_expect(
		event_checksum == publish_count * expected_per_publish,
		"EventBus 极限发布必须执行全部回调且保持载荷正确"
	)
	_record_result(
		"event_bus_publish",
		publish_count * subscriber_count,
		publish_elapsed,
		{
			"checksum": event_checksum,
			"expected_checksum": publish_count * expected_per_publish,
			"publications": publish_count,
			"subscribers": subscriber_count,
		}
	)

	bus.clear()
	started_at = Time.get_ticks_usec()
	for _index in empty_publish_count:
		bus.publish(&"performance:empty")
	_record_result(
		"event_bus_empty_publish",
		empty_publish_count,
		Time.get_ticks_usec() - started_at
	)

	# 模拟跨场景对象被释放但调用方忘记 unsubscribe；首次后续发布负责清理失效项。
	for _index in invalid_subscriber_count:
		var target := PerformanceEventNode.new()
		bus.subscribe(&"performance:invalid", target.receive)
		target.free()
	started_at = Time.get_ticks_usec()
	bus.publish(&"performance:invalid", 1)
	_record_result(
		"event_bus_invalid_cleanup",
		invalid_subscriber_count,
		Time.get_ticks_usec() - started_at,
		{"invalid_subscribers": invalid_subscriber_count}
	)
	var subscriber_map := bus.get("_subscribers") as Dictionary
	_expect(
		not subscriber_map.has(&"performance:invalid"),
		"EventBus 发布后必须移除全部失效监听"
	)
	bus.free()
#endregion

#region Registry 基准
## 测量单一大内容桶的注册、随机式循环查询与键数组复制。
func _benchmark_registry() -> void:
	var entry_count := int(_scale.registry_entries)
	var query_count := int(_scale.registry_queries)
	var registry := UFrameRegistry.new()
	var ids: Array[StringName] = []
	ids.resize(entry_count)
	for index in entry_count:
		ids[index] = StringName("performance:item_%d" % index)

	var started_at := Time.get_ticks_usec()
	for index in entry_count:
		registry.register(&"performance_item", ids[index], index + 1)
	_record_result(
		"registry_register",
		entry_count,
		Time.get_ticks_usec() - started_at,
		{"entries": entry_count}
	)

	var checksum := 0
	started_at = Time.get_ticks_usec()
	for index in query_count:
		checksum += int(registry.get_value(&"performance_item", ids[index % entry_count]))
	var query_elapsed := Time.get_ticks_usec() - started_at
	var expected_checksum := 0
	for index in query_count:
		expected_checksum += index % entry_count + 1
	_expect(checksum == expected_checksum, "Registry 大桶查询必须返回正确内容")
	_record_result(
		"registry_lookup",
		query_count,
		query_elapsed,
		{"entries": entry_count}
	)

	started_at = Time.get_ticks_usec()
	var listed_ids := registry.list_ids(&"performance_item")
	_expect(listed_ids.size() == entry_count, "Registry 键数组复制必须保留全部 ID")
	_record_result(
		"registry_list_ids",
		entry_count,
		Time.get_ticks_usec() - started_at,
		{"entries": entry_count}
	)
	registry.free()
#endregion

#region Inventory 基准
## 使用互不相同且不可堆叠的物品填满背包，形成 add_item 的最坏扫描路径。
func _benchmark_inventory() -> void:
	var item_count := int(_scale.inventory_items)
	var query_count := int(_scale.inventory_queries)
	var sort_count := int(_scale.inventory_sorts)
	var inventory := UFrameInventory.new()
	inventory.slot_count = item_count
	inventory.max_stack_size = 1
	var ids: Array[StringName] = []
	ids.resize(item_count)
	for index in item_count:
		ids[index] = StringName("performance:item_%d" % index)

	var started_at := Time.get_ticks_usec()
	for item_id in ids:
		inventory.add_item(item_id)
	_record_result(
		"inventory_fill_distinct",
		item_count,
		Time.get_ticks_usec() - started_at,
		{"slots": item_count}
	)
	_expect(inventory.get_used_slot_count() == item_count, "Inventory 极限填充必须占满全部格子")

	var checksum := 0
	started_at = Time.get_ticks_usec()
	for index in query_count:
		checksum += inventory.get_count(ids[index % item_count])
	_expect(checksum == query_count, "Inventory 数量缓存必须保持正确")
	_record_result(
		"inventory_cached_count",
		query_count,
		Time.get_ticks_usec() - started_at,
		{"slots": item_count}
	)

	started_at = Time.get_ticks_usec()
	for _index in sort_count:
		inventory.sort_and_merge()
	_record_result(
		"inventory_sort_full",
		sort_count,
		Time.get_ticks_usec() - started_at,
		{"slots": item_count, "items": item_count}
	)
	_expect(inventory.get_total_count() == item_count, "Inventory 重复整理不得改变总数量")
	# 同一份负载走批量入口，验证集中加载不必逐项扫描整个背包。
	var expected_slots := inventory.get_slots()
	inventory.clear()
	var batch: Dictionary[StringName, int] = {}
	for item_id: StringName in ids:
		batch[item_id] = 1
	started_at = Time.get_ticks_usec()
	var added := inventory.add_items(batch)
	_record_result(
		"inventory_fill_batch", item_count, Time.get_ticks_usec() - started_at,
		{"slots": item_count}
	)
	_expect(added == batch and inventory.get_total_count() == item_count, "Inventory 批量加入必须保持全部数量")
	inventory.sort_and_merge()
	_expect(inventory.get_slots() == expected_slots, "Inventory 批量与逐项加入得到相同整理结果")
	inventory.free()
#endregion

#region Stats 基准
## 把大量逆序优先级修正加入同一属性，对比批量事务与保持即时语义的逐项调用。
func _benchmark_stats() -> void:
	var modifier_count := int(_scale.stat_modifiers)
	var individual_modifier_count := int(_scale.stat_individual_modifiers)
	var query_count := int(_scale.stat_queries)
	var dirty_update_count := int(_scale.stat_dirty_updates)
	var stats := UFrameStats.new()
	stats.base_stats = {"attack": 100.0}
	var modifiers: Array[UFrameStatModifier] = []
	modifiers.resize(modifier_count)
	for index in modifier_count:
		var modifier := UFrameStatModifier.new()
		modifier.stat_name = "attack"
		modifier.operation = UFrameStatModifier.Op.ADD
		modifier.value = 1.0
		modifier.priority = modifier_count - index
		modifiers[index] = modifier

	var started_at := Time.get_ticks_usec()
	var added_count := stats.add_modifiers(modifiers)
	_record_result(
		"stats_add_batch_same_stat",
		modifier_count,
		Time.get_ticks_usec() - started_at,
		{"modifiers": modifier_count}
	)
	_expect(
		added_count == modifier_count
		and is_equal_approx(stats.get_stat("attack"), 100.0 + modifier_count),
		"Stats 大量修正后的最终值必须正确"
	)

	var checksum := 0.0
	started_at = Time.get_ticks_usec()
	for _index in query_count:
		checksum += stats.get_stat("attack")
	_expect(checksum > 0.0, "Stats 缓存查询必须产生有效结果")
	_record_result(
		"stats_cached_get",
		query_count,
		Time.get_ticks_usec() - started_at,
		{"modifiers": modifier_count}
	)

	started_at = Time.get_ticks_usec()
	for index in dirty_update_count:
		stats.set_base_stat("attack", 100.0 + float(index % 10))
	_record_result(
		"stats_dirty_recompute",
		dirty_update_count,
		Time.get_ticks_usec() - started_at,
		{"modifiers": modifier_count}
	)

	started_at = Time.get_ticks_usec()
	var removed_count := stats.remove_modifiers(modifiers)
	_record_result(
		"stats_remove_batch_same_stat",
		modifier_count,
		Time.get_ticks_usec() - started_at,
		{"modifiers": modifier_count}
	)
	_expect(
		removed_count == modifier_count and stats.get_all_modifiers().is_empty(),
		"Stats 极限批量移除后不得残留修正"
	)
	stats.free()

	# 单项 API 必须立即重算并通知，因此只使用受控规模记录它的兼容路径成本。
	var individual_stats := UFrameStats.new()
	individual_stats.base_stats = {"attack": 100.0}
	var individual_modifiers: Array[UFrameStatModifier] = []
	for index in mini(individual_modifier_count, modifiers.size()):
		individual_modifiers.append(modifiers[index])
	started_at = Time.get_ticks_usec()
	var individual_added_count := 0
	for modifier: UFrameStatModifier in individual_modifiers:
		if individual_stats.add_modifier(modifier):
			individual_added_count += 1
	_record_result(
		"stats_add_individual_same_stat",
		individual_modifiers.size(),
		Time.get_ticks_usec() - started_at,
		{"modifiers": individual_modifiers.size()}
	)
	_expect(
		individual_added_count == individual_modifiers.size(),
		"Stats 单项兼容路径必须接受每个独立修正"
	)
	individual_stats.remove_modifiers(individual_modifiers)
	individual_stats.free()

	# 独立建立一组同帧到期的修正，只测量到期扫描和移除尖峰。
	var expiring_stats := UFrameStats.new()
	expiring_stats.base_stats = {"speed": 10.0}
	var expiring_modifiers: Array[UFrameStatModifier] = []
	for index in modifier_count:
		var modifier := UFrameStatModifier.new()
		modifier.stat_name = "speed"
		modifier.operation = UFrameStatModifier.Op.ADD
		modifier.value = 0.01
		modifier.priority = index
		modifier.duration = 0.0
		expiring_modifiers.append(modifier)
	_expect(
		expiring_stats.add_modifiers(expiring_modifiers) == modifier_count,
		"Stats 必须建立完整的限时批量基准"
	)
	started_at = Time.get_ticks_usec()
	expiring_stats._process(0.0)
	_record_result(
		"stats_expire_same_frame",
		modifier_count,
		Time.get_ticks_usec() - started_at,
		{"modifiers": modifier_count}
	)
	_expect(expiring_stats.get_all_modifiers().is_empty(), "Stats 同帧到期后不得残留修正")
	expiring_stats.free()
#endregion

#region StateMachine 基准
## 测量两状态互切与普通帧、物理帧转发，不把具体玩法逻辑计入结果。
func _benchmark_state_machine() -> void:
	var transition_count := int(_scale.state_transitions)
	var dispatch_count := int(_scale.state_dispatches)
	var entity := Node.new()
	entity.name = "PerformanceEntity"
	var machine := UFrameStateMachine.new()
	machine.name = "StateMachine"
	machine.initial_state = &"A"
	var state_a := PerformanceState.new()
	state_a.name = "A"
	state_a.state_name = &"A"
	var state_b := PerformanceState.new()
	state_b.name = "B"
	state_b.state_name = &"B"
	machine.add_child(state_a)
	machine.add_child(state_b)
	entity.add_child(machine)
	add_child(entity)
	await get_tree().process_frame
	machine.set_process(false)
	machine.set_physics_process(false)
	state_a.reset_counts()
	state_b.reset_counts()

	var started_at := Time.get_ticks_usec()
	for index in transition_count:
		machine.change_state(&"B" if index % 2 == 0 else &"A")
	_record_result(
		"state_machine_transition",
		transition_count,
		Time.get_ticks_usec() - started_at
	)
	_expect(
		state_a.enter_count + state_b.enter_count == transition_count
		and state_a.exit_count + state_b.exit_count == transition_count,
		"StateMachine 极限互切必须保持 enter/exit 成对"
	)

	state_a.reset_counts()
	state_b.reset_counts()
	started_at = Time.get_ticks_usec()
	for _index in dispatch_count:
		machine._process(1.0 / 60.0)
		machine._physics_process(1.0 / 60.0)
	_record_result(
		"state_machine_dispatch",
		dispatch_count * 2,
		Time.get_ticks_usec() - started_at
	)
	_expect(
		state_a.update_count + state_b.update_count == dispatch_count
		and state_a.physics_update_count + state_b.physics_update_count == dispatch_count,
		"StateMachine 极限转发必须只调用当前状态"
	)
	entity.queue_free()
	await get_tree().process_frame
#endregion

#region Input 基准
## 测量大量同时缓冲动作的写入、活跃帧扫描、查询与统一过期。
func _benchmark_input() -> void:
	var action_count := int(_scale.input_actions)
	var frame_count := int(_scale.input_frames)
	var query_count := int(_scale.input_queries)
	var input_service := UFrameInput.new()
	input_service.name = "PerformanceInput"
	add_child(input_service)
	await get_tree().process_frame
	var actions: Array[String] = []
	actions.resize(action_count)
	for index in action_count:
		actions[index] = "performance_action_%d" % index

	var started_at := Time.get_ticks_usec()
	for action in actions:
		input_service.buffer_action(action, 2.0)
	_record_result(
		"input_buffer_unique",
		action_count,
		Time.get_ticks_usec() - started_at,
		{"actions": action_count}
	)

	started_at = Time.get_ticks_usec()
	for _index in frame_count:
		input_service._process(1.0 / 240.0)
	_record_result(
		"input_active_scan",
		action_count * frame_count,
		Time.get_ticks_usec() - started_at,
		{"actions": action_count, "frames": frame_count}
	)
	_expect(input_service.is_action_buffered(actions[0]), "Input 活跃扫描不得提前清除缓冲")

	var buffered_query_count := 0
	started_at = Time.get_ticks_usec()
	for index in query_count:
		if input_service.is_action_buffered(actions[index % action_count]):
			buffered_query_count += 1
	_expect(buffered_query_count == query_count, "Input 大量查询必须保持缓冲状态")
	_record_result(
		"input_buffer_query",
		query_count,
		Time.get_ticks_usec() - started_at,
		{"actions": action_count}
	)

	started_at = Time.get_ticks_usec()
	input_service._process(10.0)
	_record_result(
		"input_expire_all",
		action_count,
		Time.get_ticks_usec() - started_at,
		{"actions": action_count}
	)
	_expect(not input_service.is_action_buffered(actions[0]), "Input 统一过期后不得残留缓冲")
	input_service.queue_free()
	await get_tree().process_frame
#endregion

#region Pool 基准
## 测量预热、正常批量复用，以及容量满载后的最早活跃实例循环复用。
func _benchmark_pool() -> void:
	var capacity := int(_scale.pool_capacity)
	var batch_size := mini(int(_scale.pool_batch), capacity)
	var cycle_count := int(_scale.pool_cycles)
	var overflow_count := int(_scale.pool_overflow_acquires)
	var pool := UFramePool.new()
	pool.name = "PerformancePool"
	pool.pool_scene = POOL_ITEM_SCENE
	pool.initial_size = capacity
	pool.maximum_size = capacity

	var started_at := Time.get_ticks_usec()
	add_child(pool)
	var prewarm_elapsed := Time.get_ticks_usec() - started_at
	_expect(pool.get_total_count() == capacity, "Pool 预热必须达到配置容量")
	_record_result(
		"pool_prewarm",
		capacity,
		prewarm_elapsed,
		{"capacity": capacity}
	)

	var batch: Array[Node] = []
	batch.resize(batch_size)
	var successful_lifecycle_calls := 0
	started_at = Time.get_ticks_usec()
	for _cycle in cycle_count:
		for index in batch_size:
			batch[index] = pool.acquire()
			if batch[index] != null:
				successful_lifecycle_calls += 1
		for instance in batch:
			if pool.release(instance):
				successful_lifecycle_calls += 1
	var batch_elapsed := Time.get_ticks_usec() - started_at
	_expect(
		successful_lifecycle_calls == cycle_count * batch_size * 2,
		"Pool 正常批量复用不得丢失生命周期"
	)
	_record_result(
		"pool_batch_reuse",
		successful_lifecycle_calls,
		batch_elapsed,
		{"batch": batch_size, "capacity": capacity, "cycles": cycle_count}
	)

	# 先占满池，再继续 acquire，强制进入容量溢出的最早实例复用路径。
	for _index in capacity:
		pool.acquire()
	var overflow_checksum := 0
	var overflow_success_count := 0
	started_at = Time.get_ticks_usec()
	for _index in overflow_count:
		var instance := pool.acquire()
		if instance:
			overflow_success_count += 1
			overflow_checksum = overflow_checksum ^ int(instance.get_instance_id())
	var overflow_elapsed := Time.get_ticks_usec() - started_at
	_expect(
		overflow_success_count == overflow_count and overflow_checksum >= 0,
		"Pool 溢出复用必须持续返回有效实例"
	)
	_expect(
		pool.get_total_count() == capacity and pool.get_active_count() == capacity,
		"Pool 溢出复用不得突破容量"
	)
	_record_result(
		"pool_overflow_reuse",
		overflow_count,
		overflow_elapsed,
		{"capacity": capacity}
	)

	pool.clear()
	pool.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
#endregion

#region 结果与参数
## 记录单项基准；operations 应表示该结果中可以跨档位比较的最小工作单元。
func _record_result(name: String, operations: int, elapsed_usec: int, details: Dictionary = {}) -> void:
	var safe_operations := maxi(operations, 1)
	var safe_elapsed := maxi(elapsed_usec, 1)
	var result := {
		"name": name,
		"operations": operations,
		"elapsed_usec": elapsed_usec,
		"usec_per_operation": float(elapsed_usec) / float(safe_operations),
		"operations_per_second": int(float(safe_operations) * 1000000.0 / float(safe_elapsed)),
	}
	for key in details:
		result[key] = details[key]
	_result_count += 1
	print("UFRAME_PERF_RESULT %s" % JSON.stringify(result))

## 记录正确性失败；性能慢不会在这里直接判错。
func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	push_error("[UFramePerformance] %s" % message)

## 解析 [code]--profile=quick|standard|stress[/code] 与逗号分隔的 [code]--only[/code]。
func _parse_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--profile="):
			_profile_name = argument.trim_prefix("--profile=").strip_edges().to_lower()
		elif argument.begins_with("--only="):
			for scenario in argument.trim_prefix("--only=").split(",", false):
				var scenario_name := StringName(scenario.strip_edges())
				if not scenario_name.is_empty():
					_selected_scenarios[scenario_name] = true
	for scenario in _selected_scenarios:
		if not SCENARIO_NAMES.has(scenario):
			push_warning("[UFramePerformance] 未知场景会被忽略：%s" % scenario)

## 判断当前基准是否被命令行筛选。
func _should_run(scenario: StringName) -> bool:
	return _selected_scenarios.is_empty() or _selected_scenarios.has(scenario)

## 输出可复现实验所需的引擎、系统、档位与初始监视器信息。
func _print_environment() -> void:
	var version_info := Engine.get_version_info()
	var environment := {
		"profile": _profile_name,
		"godot": String(version_info.get("string", "unknown")),
		"os": OS.get_name(),
		"processor_count": OS.get_processor_count(),
		"debug_build": OS.is_debug_build(),
		"display_server": DisplayServer.get_name(),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"static_memory_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
	}
	print("UFRAME_PERF_BEGIN %s" % JSON.stringify(environment))
#endregion
