extends Node

## UFrame 的无第三方依赖回归测试。覆盖核心不变量、历史故障和主要可选模块。

class LifecycleBehavior extends UFrameBehavior:
	var enter_count := 0
	var exit_count := 0
	var update_count := 0
	var physics_update_count := 0
	var last_entered_entity: Node
	var entered_after_entity_ready := false
	var events: Array[String] = []

	func on_enter() -> void:
		enter_count += 1
		last_entered_entity = entity
		entered_after_entity_ready = entity != null and entity.is_node_ready()
		events.append("enter")

	func on_exit() -> void:
		exit_count += 1
		events.append("exit")

	func on_update(_delta: float) -> void:
		update_count += 1

	func on_physics_update(_delta: float) -> void:
		physics_update_count += 1

class StateUpdateProbe extends UFrameState:
	var setup_count := 0
	var enter_count := 0
	var update_count := 0
	var physics_update_count := 0
	var setup_machine: Node
	var setup_entity: Node
	var lifecycle_events: Array[String] = []

	func on_setup() -> void:
		setup_count += 1
		setup_machine = state_machine
		setup_entity = entity
		lifecycle_events.append("setup")

	func on_enter(_data := {}) -> void:
		enter_count += 1
		lifecycle_events.append("enter")

	func on_update(_delta: float) -> void:
		update_count += 1

	func on_physics_update(_delta: float) -> void:
		physics_update_count += 1

var _failures := 0
var _arena_dust_events := 0

func _ready() -> void:
	_test_runtime()
	_test_event_bus()
	_test_stats()
	_test_inventory()
	_test_inventory_transactions()
	_test_loot_table()
	_test_spider_rules()
	_test_registry()
	await _test_health_and_hitboxes()
	await _test_pool()
	_test_arena_scene_composition()
	await _test_arena_behavior_runtime()
	_test_platform_and_loot_scene_composition()
	await _test_platform_air_state_runtime()
	_test_spider_scene_composition()
	await _test_spider_runtime()
	await _test_camera()
	await _test_input()
	await _test_transition_overlay()
	await _test_state_machine()
	await _test_behavior_lifecycle()
	await _test_audio_volume()
	_test_save_recovery()
	# 给 queue_free、音频播放流和延迟信号足够的清理帧，确保测试退出时没有伪泄漏警告。
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if _failures == 0:
		print("UFRAME_TESTS_OK")
		get_tree().quit(0)
	else:
		push_error("UFrame tests failed: %d" % _failures)
		get_tree().quit(1)

func _test_runtime() -> void:
	_expect(UFrame.events != null, "event bus is always available")
	_expect(UFrame.registry != null, "registry follows example project setting")
	_expect((UFrame.input != null) == UFrame.is_module_enabled("input"), "optional input module follows setting")
	_expect(UFrame.VERSION == "0.4.0", "runtime version")

func _test_event_bus() -> void:
	var bus := UFrameEventBus.new()
	var received: Array = []
	var callback := func(value: Variant) -> void: received.append(value)
	bus.subscribe(&"test", callback)
	bus.subscribe(&"test", callback)
	bus.publish(&"test", 42)
	_expect(received == [42], "event subscriptions are deduplicated")
	bus.unsubscribe(&"test", callback)
	bus.publish(&"test", 7)
	_expect(received == [42], "event unsubscribe")
	var recursive_count := [0]
	var recursive_callback: Callable
	recursive_callback = func() -> void:
		recursive_count[0] += 1
		bus.publish(&"once_recursive")
	bus.subscribe(&"once_recursive", recursive_callback, true)
	bus.publish(&"once_recursive")
	_expect(recursive_count[0] == 1, "once subscriber is removed before recursive publish")
	bus.free()

func _test_stats() -> void:
	var stats := UFrameStats.new()
	stats.base_stats = {"attack": 100.0}
	var modifier := UFrameStatModifier.new()
	modifier.stat_name = "attack"
	modifier.operation = UFrameStatModifier.Op.PERCENT
	modifier.value = 0.5
	stats.add_modifier(modifier)
	_expect(is_equal_approx(stats.get_stat("attack"), 150.0), "stat modifier")
	stats.remove_modifier(modifier)
	_expect(is_equal_approx(stats.get_stat("attack"), 100.0), "stat cache invalidation")
	stats.free()

func _test_inventory() -> void:
	var inventory := UFrameInventory.new()
	inventory.slot_count = 1
	inventory.max_stack_size = 3
	_expect(inventory.add_item(&"potion", 5) == 3, "inventory respects capacity")
	_expect(inventory.get_total_count() == 3, "inventory caches total count")
	var change_count := [0]
	inventory.inventory_changed.connect(func() -> void: change_count[0] += 1)
	_expect(inventory.consume_item(&"potion", 2), "inventory consumes available items")
	_expect(change_count[0] == 1, "consume commits one aggregate change")
	_expect(not inventory.consume_item(&"potion", 2), "inventory rejects insufficient consume")
	inventory.free()

func _test_inventory_transactions() -> void:
	var inventory := UFrameInventory.new()
	inventory.slot_count = 4
	inventory.set_stack_limit(&"material", 64)
	_expect(inventory.set_slots([
		{"item_id": &"material", "count": 32}, {}, {}, {"item_id": &"material", "count": 8},
	]), "valid slots restore")
	inventory.slot_count = 3
	_expect(inventory.slot_count == 4 and inventory.get_count(&"material") == 40, "occupied shrink is rejected without ghost totals")
	_expect(not inventory.set_stack_limit(&"material", 8), "stack rule that cannot fit is rejected")
	_expect(inventory.get_stack_limit(&"material") == 64 and inventory.get_total_count() == 40, "failed stack rule preserves content")
	var before := inventory.get_slots()
	_expect(not inventory.set_slots([{"item_id": &"material", "count": 65}]), "invalid save is rejected")
	_expect(inventory.get_slots() == before, "failed restore is transactional")
	inventory.set_stack_limit(&"potion", 16)
	inventory.add_item(&"potion", 9)
	_expect(inventory.sort_and_merge(func(id: StringName) -> String: return "0" if id == &"potion" else "1"), "custom category sort succeeds")
	_expect(inventory.get_slot(0).item_id == &"potion", "custom sort key controls group order")
	inventory.free()

func _test_loot_table() -> void:
	var entry := UFrameLootEntry.new()
	entry.content_id = &"coin"
	entry.weight = 1.0
	entry.min_count = 2
	entry.max_count = 2
	var table := UFrameLootTable.new()
	table.entries = [entry]
	table.no_drop_weight = 1000000.0
	table.pity_count = 1
	table.pity_entry_index = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var miss := table.roll(0, rng)
	_expect(miss.count == 0 and miss.miss_count == 1, "loot table reports caller-owned miss state")
	var pity_result := table.roll(miss.miss_count, rng)
	_expect(pity_result.content_id == &"coin" and pity_result.count == 2 and pity_result.pity_triggered, "loot pity triggers from explicit state")
	var independent := table.roll(0, rng)
	_expect(not independent.pity_triggered, "shared LootTable does not share runtime pity state")


func _test_spider_rules() -> void:
	var model := SpiderGameModel.new()
	model.new_game(20260801)

	# 初始牌局使用完整 104 张牌：前四列 6 张，其余列 5 张，且每列仅顶牌朝上。
	var seen_ids := {}
	var initial_distribution_valid := true
	var initial_faces_valid := true
	var tableau_card_count := 0
	for column_index in SpiderGameModel.COLUMN_COUNT:
		var column: Array = model.columns[column_index]
		var expected_size := 6 if column_index < 4 else 5
		initial_distribution_valid = initial_distribution_valid and column.size() == expected_size
		tableau_card_count += column.size()
		for card_index in column.size():
			var card := column[card_index] as Dictionary
			var id := int(card.get("id", -1))
			seen_ids[id] = true
			initial_faces_valid = initial_faces_valid and (
				bool(card.get("face_up", false)) == (card_index == column.size() - 1)
			)
	for card: Dictionary in model.stock:
		seen_ids[int(card.get("id", -1))] = true
	_expect(initial_distribution_valid and tableau_card_count == 54, "spider initial tableau uses 6/6/6/6 then six 5-card columns")
	_expect(initial_faces_valid, "spider initial tableau reveals only each column top")
	_expect(model.stock.size() == 50 and model.get_stock_deals_remaining() == 5, "spider initial stock keeps five complete deals")
	_expect(tableau_card_count + model.stock.size() == 104 and seen_ids.size() == 104, "spider initial state owns all 104 unique card IDs")
	_expect(not model.can_undo(), "spider new game starts without undo history")
	var valid_initial := model.capture_state()
	var bad_restore := valid_initial.duplicate(true)
	var bad_columns := bad_restore["columns"] as Array
	(bad_columns[0][0] as Dictionary)["id"] = int((bad_columns[1][0] as Dictionary)["id"])
	_expect(not model.restore_state(bad_restore) and model.capture_state() == valid_initial, "spider rejects duplicate-ID save data transactionally")
	bad_restore = valid_initial.duplicate(true)
	bad_columns = bad_restore["columns"] as Array
	(bad_columns[0][0] as Dictionary)["face_up"] = true
	_expect(not model.restore_state(bad_restore) and model.capture_state() == valid_initial, "spider rejects a hidden card above a revealed card")
	model.new_game(0)
	var zero_seed_state := model.capture_state()
	model.new_game(0)
	_expect(model.capture_state() == zero_seed_state, "spider treats zero as a reproducible seed")

	_test_spider_move_and_undo(model)
	_test_spider_deal_and_undo(model)
	_test_spider_completion_and_undo(model)
	_test_spider_difficulty_rules()
	_test_spider_auto_move_rules()


## 多花色蜘蛛纸牌有一个容易写错的边界：单张牌只需按点数接龙，
## 但一次移动多张牌与自动收组都必须同花。这里把三档牌组和这两层规则一起锁住。
func _test_spider_difficulty_rules() -> void:
	var model := SpiderGameModel.new()
	var reproducible_seed := 20260802
	for suit_count_value in SpiderGameModel.VALID_SUIT_COUNTS:
		var suit_count := int(suit_count_value)
		model.new_game(reproducible_seed, suit_count)
		var first_state := model.capture_state()
		var suit_totals: Array[int] = []
		var rank_totals: Array = []
		for _suit_index in suit_count:
			suit_totals.append(0)
			var ranks: Array[int] = []
			for _rank_index in SpiderGameModel.CARDS_PER_RUN:
				ranks.append(0)
			rank_totals.append(ranks)

		var all_cards: Array = []
		for column in model.columns:
			all_cards.append_array(column)
		all_cards.append_array(model.stock)
		var distribution_valid := all_cards.size() == SpiderGameModel.TOTAL_RUNS * SpiderGameModel.CARDS_PER_RUN
		for raw_card in all_cards:
			var card := raw_card as Dictionary
			var suit := int(card.get("suit", -1))
			var rank := int(card.get("rank", 0))
			if suit < 0 or suit >= suit_count or rank < 1 or rank > SpiderGameModel.CARDS_PER_RUN:
				distribution_valid = false
				continue
			suit_totals[suit] += 1
			(rank_totals[suit] as Array)[rank - 1] += 1

		var expected_copies: int = SpiderGameModel.TOTAL_RUNS / suit_count
		for suit in suit_count:
			distribution_valid = distribution_valid and suit_totals[suit] == expected_copies * SpiderGameModel.CARDS_PER_RUN
			for rank_index in SpiderGameModel.CARDS_PER_RUN:
				distribution_valid = distribution_valid and int((rank_totals[suit] as Array)[rank_index]) == expected_copies
		_expect(distribution_valid, "spider %d-suit deck keeps the standard 104-card distribution" % suit_count)
		_expect(model.suit_count == suit_count and int(first_state.get("suit_count", 0)) == suit_count, "spider %d-suit difficulty is explicit in runtime and snapshots" % suit_count)
		model.new_game(reproducible_seed, suit_count)
		_expect(model.capture_state() == first_state, "spider %d-suit game is reproducible from a fixed seed" % suit_count)

	_test_spider_multisuit_moves(model)
	_test_spider_multisuit_completion(model)
	_test_spider_difficulty_restore_and_undo(model)


## 右键自动移动只负责选择目标，真正提交仍交给 move_stack()。
## 这里固定控制十列顶部，避免随机填充牌意外形成另一个同点数目标。
func _test_spider_auto_move_rules() -> void:
	var model := SpiderGameModel.new()
	model.new_game(20260806, 2)
	var source_cards: Array = [
		_spider_suited_card(0, 4, 0, 2, true),
		_spider_suited_card(0, 3, 0, 2, true),
		_spider_suited_card(0, 2, 0, 2, true),
		_spider_suited_card(0, 1, 0, 2, true),
	]
	var required := _empty_spider_columns()
	required[0] = source_cards
	# 异花色 5 放在更靠左的列，同花色 5 仍必须优先。
	required[1] = [_spider_suited_card(1, 5, 0, 2, true)]
	required[2] = [_spider_suited_card(0, 5, 0, 2, true)]
	for column_index in range(3, SpiderGameModel.COLUMN_COUNT):
		var filler_suit: int = column_index % 2
		var filler_rank: int = 6 + (column_index - 3) % 7
		required[column_index] = [_spider_suited_card(filler_suit, filler_rank, 1, 2, true)]
	var same_suit_fixture := _make_spider_fixture(model, required)
	if not _expect_spider_restore(model, same_suit_fixture, "spider restores same-suit auto-move fixture"):
		return
	var source_index := model.columns[0].size() - source_cards.size()
	_expect(model.find_auto_move_target(0, source_index) == 2, "spider auto-move prefers a same-suit rank target")
	var before_move := model.capture_state()
	var auto_result := model.move_stack(0, source_index, model.find_auto_move_target(0, source_index))
	_expect(bool(auto_result.get("success", false)) and (auto_result.get("moved_ids", []) as Array).size() == 4, "spider auto-move target moves the complete clicked suffix")
	_expect(bool(model.undo().get("success", false)) and model.capture_state() == before_move, "spider auto-move remains one normal undoable move")

	# 没有同花色 5 时回退到其他花色的 5，而不是先选空列。
	required[2] = [_spider_suited_card(0, 7, 0, 2, true)]
	var other_suit_fixture := _make_spider_fixture(model, required)
	if not _expect_spider_restore(model, other_suit_fixture, "spider restores other-suit auto-move fixture"):
		return
	source_index = model.columns[0].size() - source_cards.size()
	_expect(model.find_auto_move_target(0, source_index) == 1, "spider auto-move falls back to another suit with the required rank")

	# 控制每个非空列的顶牌都不是 5，再留出 Column10，验证最后才使用空列。
	required = _empty_spider_columns()
	required[0] = source_cards
	for column_index in range(1, SpiderGameModel.COLUMN_COUNT):
		var suit: int = column_index % 2
		var rank: int = 6 + (column_index - 1) % 7
		var copy: int = int((column_index - 1) / 2) % 4
		required[column_index] = [_spider_suited_card(suit, rank, copy, 2, true)]
	var empty_fixture := _make_spider_fixture(model, required)
	var fixture_columns := empty_fixture["columns"] as Array
	var merged_column := fixture_columns[8] as Array
	merged_column.append_array(fixture_columns[9] as Array)
	for card_value in merged_column:
		(card_value as Dictionary)["face_up"] = false
	(merged_column.back() as Dictionary)["face_up"] = true
	fixture_columns[9] = []
	if not _expect_spider_restore(model, empty_fixture, "spider restores empty-column auto-move fixture"):
		return
	source_index = model.columns[0].size() - source_cards.size()
	_expect(model.find_auto_move_target(0, source_index) == 9, "spider auto-move uses the leftmost empty column only after rank targets fail")

	# 右键点到混花后缀时不能偷偷缩短牌组，查询也不能产生历史或数据变化。
	required = _empty_spider_columns()
	required[0] = [
		_spider_suited_card(0, 4, 0, 2, true),
		_spider_suited_card(1, 3, 0, 2, true),
	]
	required[1] = [_spider_suited_card(0, 5, 0, 2, true)]
	var broken_fixture := _make_spider_fixture(model, required)
	if not _expect_spider_restore(model, broken_fixture, "spider restores broken auto-move fixture"):
		return
	source_index = model.columns[0].size() - 2
	var before_query := model.capture_state()
	_expect(
		model.find_auto_move_target(0, source_index) == -1
		and model.find_auto_move_target(-1, 0) == -1
		and model.capture_state() == before_query
		and not model.can_undo(),
		"spider auto-move query rejects broken input without changing state"
	)


func _test_spider_multisuit_moves(model: SpiderGameModel) -> void:
	model.new_game(20260803, 2)
	var required := _empty_spider_columns()
	# 黑桃 6 可以单独接到红桃 7 上；目标牌的花色不会阻止单张接龙。
	required[0] = [_spider_suited_card(1, 6, 0, 2, true)]
	required[1] = [_spider_suited_card(0, 7, 0, 2, true)]
	var fixture := _make_spider_fixture(model, required)
	if not _expect_spider_restore(model, fixture, "spider restores two-suit single-card fixture"):
		return
	var source_index := model.columns[0].size() - 1
	_expect(model.can_move(0, source_index, 1), "spider allows one card to connect across suits when ranks match")
	var single_result := model.move_stack(0, source_index, 1)
	_expect(bool(single_result.get("success", false)), "spider executes a legal cross-suit single-card move")

	# 7-6 点数虽然连续，但花色不同，不能把两张当作一个后缀整体拖走。
	required = _empty_spider_columns()
	required[0] = [
		_spider_suited_card(0, 7, 0, 2, true),
		_spider_suited_card(1, 6, 0, 2, true),
	]
	required[1] = [_spider_suited_card(0, 8, 0, 2, true)]
	fixture = _make_spider_fixture(model, required)
	if not _expect_spider_restore(model, fixture, "spider restores mixed-suit sequence fixture"):
		return
	source_index = model.columns[0].size() - 2
	_expect(not model.is_movable_sequence(0, source_index), "spider rejects a descending suffix whose suits are mixed")
	var mixed_before := model.capture_state()
	var mixed_result := model.move_stack(0, source_index, 1)
	_expect(
		not bool(mixed_result.get("success", false))
		and mixed_result.get("reason") == "broken_sequence"
		and model.capture_state() == mixed_before,
		"spider mixed-suit stack move is transactional"
	)

	# 同花 7-6 可以整体移动到任意花色的 8 上；目标花色仍不参与接牌判断。
	required = _empty_spider_columns()
	required[0] = [
		_spider_suited_card(1, 7, 0, 2, true),
		_spider_suited_card(1, 6, 0, 2, true),
	]
	required[1] = [_spider_suited_card(0, 8, 0, 2, true)]
	fixture = _make_spider_fixture(model, required)
	if not _expect_spider_restore(model, fixture, "spider restores same-suit sequence fixture"):
		return
	source_index = model.columns[0].size() - 2
	_expect(model.is_movable_sequence(0, source_index) and model.can_move(0, source_index, 1), "spider accepts a same-suit descending suffix as one movable stack")
	var same_suit_result := model.move_stack(0, source_index, 1)
	_expect(bool(same_suit_result.get("success", false)) and (same_suit_result.get("moved_ids", []) as Array).size() == 2, "spider moves the complete same-suit suffix")


func _test_spider_multisuit_completion(model: SpiderGameModel) -> void:
	model.new_game(20260804, 2)
	var required := _empty_spider_columns()
	var mixed_run: Array = []
	for rank in range(13, 1, -1):
		# 只把中间的 7 换成另一花色；点数仍是完整 K 到 2。
		var suit := 1 if rank == 7 else 0
		mixed_run.append(_spider_suited_card(suit, rank, 0, 2, true))
	required[0] = mixed_run
	required[1] = [_spider_suited_card(0, 1, 0, 2, true)]
	var fixture := _make_spider_fixture(model, required)
	if not _expect_spider_restore(model, fixture, "spider restores mixed-suit completion fixture"):
		return
	var ace_index := model.columns[1].size() - 1
	var mixed_result := model.move_stack(1, ace_index, 0)
	_expect(
		bool(mixed_result.get("success", false))
		and int(mixed_result.get("completed_delta", 0)) == 0
		and (mixed_result.get("removed_ids", []) as Array).is_empty()
		and model.completed_runs == 0,
		"spider does not collect a mixed-suit K-to-A run"
	)

	required = _empty_spider_columns()
	var same_suit_run: Array = []
	for rank in range(13, 1, -1):
		same_suit_run.append(_spider_suited_card(0, rank, 0, 2, true))
	required[0] = same_suit_run
	required[1] = [_spider_suited_card(0, 1, 0, 2, true)]
	fixture = _make_spider_fixture(model, required)
	if not _expect_spider_restore(model, fixture, "spider restores same-suit completion fixture"):
		return
	ace_index = model.columns[1].size() - 1
	var same_suit_result := model.move_stack(1, ace_index, 0)
	_expect(
		bool(same_suit_result.get("success", false))
		and int(same_suit_result.get("completed_delta", 0)) == 1
		and (same_suit_result.get("removed_ids", []) as Array).size() == SpiderGameModel.CARDS_PER_RUN
		and model.completed_runs == 1,
		"spider collects only a same-suit K-to-A run"
	)


func _test_spider_difficulty_restore_and_undo(model: SpiderGameModel) -> void:
	model.new_game(20260805, 4)
	var four_suit_state := model.capture_state()
	model.new_game(20260805, 1)
	_expect(
		model.restore_state(four_suit_state)
		and model.suit_count == 4
		and model.capture_state() == four_suit_state,
		"spider restore switches back to the difficulty saved in the snapshot"
	)

	var before_deal := model.capture_state()
	var deal_result := model.deal_stock()
	# suit_count 是公开只读约定而非私有字段；此处故意改写它，验证 undo() 确实从历史
	# 恢复难度，而不是碰巧沿用当前变量。
	model.suit_count = 1
	var undo_result := model.undo()
	_expect(
		bool(deal_result.get("success", false))
		and bool(undo_result.get("success", false))
		and model.suit_count == 4
		and model.capture_state() == before_deal,
		"spider undo restores difficulty together with cards, stock and score"
	)


func _test_spider_move_and_undo(model: SpiderGameModel) -> void:
	var required := _empty_spider_columns()
	# Column01 顶部为暗牌、7、6；Column02 顶部为 8，因此可移动 7-6。
	required[0] = [_spider_card(22, false), _spider_card(6, true), _spider_card(5, true)]
	required[1] = [_spider_card(7, true)]
	# Column03 顶部为 4，用来验证目标点数不匹配时必须保持原局面。
	required[2] = [_spider_card(3, true)]
	var fixture := _make_spider_fixture(model, required)
	if not _expect_spider_restore(model, fixture, "spider restores valid move fixture"):
		return

	var before := model.capture_state()
	var start_index := model.columns[0].size() - 2
	_expect(model.can_move(0, start_index, 1), "spider accepts a face-up descending stack onto the next rank")
	var result := model.move_stack(0, start_index, 1)
	var source: Array = model.columns[0]
	var destination: Array = model.columns[1]
	var moved_to_destination: bool = (
		_spider_id(destination[destination.size() - 3]) == 7
		and _spider_id(destination[destination.size() - 2]) == 6
		and _spider_id(destination.back()) == 5
	)
	var moved_ids := result.get("moved_ids", []) as Array
	var flipped_ids := result.get("flipped_ids", []) as Array
	_expect(bool(result.get("success", false)) and moved_ids == [6, 5] and moved_to_destination, "spider moves the requested stack without recreating cards")
	_expect(_spider_id(source.back()) == 22 and _spider_is_face_up(source.back()) and flipped_ids.has(22), "spider reveals the newly exposed source card")
	_expect(model.can_undo(), "spider successful move creates one undo transaction")
	var undo_result := model.undo()
	_expect(bool(undo_result.get("success", false)) and model.capture_state() == before, "spider undo restores movement, reveal, score and move count atomically")

	# restore_state() 会清空历史；失败动作不能改变局面，也不能制造一条空撤销记录。
	_expect(model.restore_state(before), "spider restores move fixture before invalid action")
	var invalid_before := model.capture_state()
	_expect(not model.can_move(0, start_index, 2), "spider rejects a stack whose destination rank does not match")
	var invalid_result := model.move_stack(0, start_index, 2)
	_expect(not bool(invalid_result.get("success", false)) and invalid_result.get("reason") == "rank_mismatch", "spider reports the illegal move reason")
	_expect(model.capture_state() == invalid_before and not model.can_undo(), "spider illegal move leaves state and undo history untouched")


func _test_spider_deal_and_undo(model: SpiderGameModel) -> void:
	var fixture := _make_spider_fixture(model, _empty_spider_columns())
	if not _expect_spider_restore(model, fixture, "spider restores valid deal fixture"):
		return
	var before := model.capture_state()
	var sizes_before := PackedInt32Array()
	for column in model.columns:
		sizes_before.append(column.size())
	_expect(model.can_deal(), "spider allows dealing when all columns are occupied")
	var deal_result := model.deal_stock()
	var deal_ids := deal_result.get("moved_ids", []) as Array
	var dealt_one_to_each_column: bool = bool(deal_result.get("success", false)) and deal_ids.size() == 10 and model.stock.size() == 40
	for column_index in SpiderGameModel.COLUMN_COUNT:
		var column: Array = model.columns[column_index]
		dealt_one_to_each_column = dealt_one_to_each_column and column.size() == sizes_before[column_index] + 1
		dealt_one_to_each_column = dealt_one_to_each_column and _spider_is_face_up(column.back())
	_expect(dealt_one_to_each_column, "spider deal places one face-up stock card on every column")
	var undo_result := model.undo()
	_expect(bool(undo_result.get("success", false)) and model.capture_state() == before, "spider undo restores all ten dealt cards and stock order")

	# 制造一个仍然拥有 104 个唯一 ID 的合法空列快照，而不是使用不完整测试牌组。
	var empty_column_state := before.duplicate(true)
	var state_columns: Array = empty_column_state["columns"]
	var displaced: Array = state_columns[9]
	var merged: Array = []
	for raw_card in displaced:
		var card := (raw_card as Dictionary).duplicate(true)
		card["face_up"] = false
		merged.append(card)
	merged.append_array(state_columns[8])
	state_columns[8] = merged
	state_columns[9] = []
	if not _expect_spider_restore(model, empty_column_state, "spider restores valid empty-column fixture"):
		return
	var blocked_before := model.capture_state()
	_expect(not model.can_deal(), "spider blocks stock deal while any tableau column is empty")
	var blocked_result := model.deal_stock()
	_expect(not bool(blocked_result.get("success", false)) and blocked_result.get("reason") == "empty_column", "spider reports empty column as deal blocker")
	_expect(model.capture_state() == blocked_before and not model.can_undo(), "blocked spider deal does not consume stock or create history")


func _test_spider_completion_and_undo(model: SpiderGameModel) -> void:
	var required := _empty_spider_columns()
	# Column01 为暗牌 + K 到 2，Column02 顶部为 A；移动 A 会完成并自动收走整组。
	var almost_complete: Array = [_spider_card(17, false)]
	for id in range(12, 0, -1):
		almost_complete.append(_spider_card(id, true))
	required[0] = almost_complete
	required[1] = [_spider_card(0, true)]
	var fixture := _make_spider_fixture(model, required)
	if not _expect_spider_restore(model, fixture, "spider restores completion fixture"):
		return
	var before := model.capture_state()
	var ace_index := model.columns[1].size() - 1
	_expect(model.can_move(1, ace_index, 0), "spider accepts Ace onto an exposed 2")
	var result := model.move_stack(1, ace_index, 0)
	var target: Array = model.columns[0]
	var removed_ids := result.get("removed_ids", []) as Array
	var flipped_ids := result.get("flipped_ids", []) as Array
	var completed_correctly: bool = (
		bool(result.get("success", false))
		and int(result.get("completed_delta", 0)) == 1
		and removed_ids.size() == SpiderGameModel.CARDS_PER_RUN
		and model.completed_runs == 1
	)
	_expect(completed_correctly, "spider automatically collects a face-up K-to-A run")
	_expect(_spider_id(target.back()) == 17 and _spider_is_face_up(target.back()) and flipped_ids.has(17), "spider reveals the card exposed by automatic collection")
	var undo_result := model.undo()
	_expect(bool(undo_result.get("success", false)) and model.capture_state() == before, "spider undo restores triggering move, completed run and exposed card together")


## 构造完整生产快照：始终保留 54 张桌面牌、50 张库存牌和全部唯一 ID。
## required_columns 中的牌会按给定顺序放在对应列顶部，其余牌作为暗牌填在下方。
func _make_spider_fixture(model: SpiderGameModel, required_columns: Array) -> Dictionary:
	var state := model.capture_state()
	var suit_count := int(state.get("suit_count", 1))
	var fixture_columns: Array = []
	var used_ids := {}
	var required_count := 0
	for column_index in SpiderGameModel.COLUMN_COUNT:
		fixture_columns.append([])
		var required: Array = required_columns[column_index]
		for card in required:
			used_ids[_spider_id(card)] = true
			required_count += 1

	var available_ids: Array[int] = []
	for id in 104:
		if not used_ids.has(id):
			available_ids.append(id)
	var filler_count := 54 - required_count
	for filler_index in filler_count:
		var filler_column: Array = fixture_columns[filler_index % SpiderGameModel.COLUMN_COUNT]
		filler_column.append(_spider_card(available_ids[filler_index], false, suit_count))
	for column_index in SpiderGameModel.COLUMN_COUNT:
		var required: Array = required_columns[column_index]
		var fixture_column: Array = fixture_columns[column_index]
		if required.is_empty():
			var top_index: int = fixture_column.size() - 1
			(fixture_column[top_index] as Dictionary)["face_up"] = true
		else:
			fixture_column.append_array(required)

	var stock: Array = []
	for index in range(filler_count, available_ids.size()):
		stock.append(_spider_card(available_ids[index], false, suit_count))
	state["columns"] = fixture_columns
	state["stock"] = stock
	state["completed_runs"] = 0
	state["move_count"] = 0
	state["score"] = SpiderGameModel.INITIAL_SCORE
	return state


func _empty_spider_columns() -> Array:
	var columns: Array = []
	for _column_index in SpiderGameModel.COLUMN_COUNT:
		columns.append([])
	return columns


func _spider_card(id: int, face_up: bool, suit_count := 1) -> Dictionary:
	var copies_per_suit := SpiderGameModel.TOTAL_RUNS / suit_count
	return {
		"id": id,
		"rank": id % SpiderGameModel.CARDS_PER_RUN + 1,
		"suit": id / (copies_per_suit * SpiderGameModel.CARDS_PER_RUN),
		"face_up": face_up,
	}


## 由“花色、点数、同花色内的副本编号”生成生产模型使用的唯一 ID。
## 测试不伪造随意 ID，因此 restore_state() 也覆盖真实存档校验路径。
func _spider_suited_card(suit: int, rank: int, copy: int, suit_count: int, face_up: bool) -> Dictionary:
	var copies_per_suit := SpiderGameModel.TOTAL_RUNS / suit_count
	var id := (suit * copies_per_suit + copy) * SpiderGameModel.CARDS_PER_RUN + rank - 1
	return _spider_card(id, face_up, suit_count)


func _spider_id(card: Variant) -> int:
	return int((card as Dictionary).get("id", -1))


func _spider_is_face_up(card: Variant) -> bool:
	return bool((card as Dictionary).get("face_up", false))


func _expect_spider_restore(model: SpiderGameModel, state: Dictionary, message: String) -> bool:
	var restored := model.restore_state(state)
	_expect(restored, message)
	return restored

func _test_registry() -> void:
	var registry := UFrameRegistry.new()
	var value := Resource.new()
	_expect(registry.register(&"item", &"game:potion", value), "registry accepts valid content")
	_expect(registry.get_value(&"item", &"game:potion") == value, "registry retrieves content")
	_expect(registry.unregister(&"item", &"game:potion"), "registry unregister")
	registry.free()

func _test_health_and_hitboxes() -> void:
	var entity := Node2D.new()
	add_child(entity)
	var health := UFrameHealth.new()
	health.name = "HealthComponent"
	health.max_hp = 3
	entity.add_child(health)
	var hurtbox := UFrameHurtbox2D.new()
	hurtbox.name = "HurtboxComponent"
	entity.add_child(hurtbox)
	var hitbox := UFrameHitbox2D.new()
	hitbox.damage = 2
	add_child(hitbox)
	await get_tree().process_frame
	var confirmed := [0]
	hitbox.hit_confirmed.connect(func(_target: Node, damage: int) -> void: confirmed[0] += damage)
	hurtbox.call("_on_area_entered", hitbox)
	_expect(health.hp == 1 and confirmed[0] == 2, "hurtbox confirms only applied local damage")
	hurtbox.call("_on_area_entered", hitbox)
	_expect(health.hp == 1 and confirmed[0] == 2, "hit once prevents duplicate damage")
	_expect(health.take_damage(5) == 1 and health.hp == 0, "health returns clamped actual damage")
	health.set_max_hp(1, false)
	_expect(health.hp == 0, "lower max hp keeps current hp clamped")
	health.invincible_duration = 10.0
	health.reset()
	_expect(health.hp == 1 and not health.is_invincible(), "health reset revives pooled entity")
	_expect(health.take_damage(1) == 1 and health.is_invincible(), "health starts configured invincibility")
	health.reset()
	_expect(health.hp == 1 and not health.is_invincible(), "health reset clears stale invincibility")
	hitbox.queue_free()
	entity.queue_free()
	await get_tree().process_frame

	# Team 是可选组件：双方都有 Team 时过滤友军，缺少 Team 时保持旧行为。
	var target_entity := Node2D.new()
	add_child(target_entity)
	var target_health := UFrameHealth.new()
	target_health.name = "HealthComponent"
	target_health.max_hp = 2
	target_entity.add_child(target_health)
	var target_team := UFrameTeam.new()
	target_team.name = "TeamComponent"
	target_team.team_id = 1
	target_entity.add_child(target_team)
	var team_hurtbox := UFrameHurtbox2D.new()
	team_hurtbox.name = "HurtboxComponent"
	target_entity.add_child(team_hurtbox)
	var source_entity := Node2D.new()
	add_child(source_entity)
	var source_team := UFrameTeam.new()
	source_team.name = "TeamComponent"
	source_team.team_id = 1
	source_entity.add_child(source_team)
	var team_hitbox := UFrameHitbox2D.new()
	team_hitbox.damage = 1
	source_entity.add_child(team_hitbox)
	await get_tree().process_frame
	_expect(team_hurtbox.receive_hit(team_hitbox) == 0 and target_health.hp == 2, "hurtbox team filter rejects friendly fire")
	source_team.set_team(2)
	team_hitbox.reset_hits()
	_expect(team_hurtbox.receive_hit(team_hitbox) == 1 and target_health.hp == 1, "hurtbox team filter accepts hostile source")
	source_entity.queue_free()
	target_entity.queue_free()
	await get_tree().process_frame

func _test_pool() -> void:
	var template := Area2D.new()
	var packed := PackedScene.new()
	_expect(packed.pack(template) == OK, "pack pool fixture")
	template.free()
	var pool := UFramePool.new()
	pool.pool_scene = packed
	pool.initial_size = 3
	pool.maximum_size = 2
	add_child(pool)
	await get_tree().process_frame
	_expect(pool.get_total_count() == 2, "pool prewarm respects maximum")
	var first := pool.acquire() as Area2D
	var second := pool.acquire() as Area2D
	_expect(
		first != null
		and first.can_process()
		and PhysicsServer2D.area_get_space(first.get_rid()).is_valid(),
		"pool acquire restores Area2D through Godot processing"
	)
	_expect(second != null and pool.get_active_count() == 2, "pool can activate every prewarmed instance")
	var first_recycled := pool.acquire() as Area2D
	_expect(first_recycled == first and pool.get_total_count() == 2, "pool automatically recycles the oldest active instance at capacity")
	_expect(pool.release(first_recycled), "pool release")
	_expect(
		not first.can_process()
		and not PhysicsServer2D.area_get_space(first.get_rid()).is_valid()
		and first.monitoring
		and first.monitorable,
		"pool lets Godot remove idle Area2D without rewriting its settings"
	)
	_expect(not pool.release(first), "pool rejects duplicate release")
	first.queue_free()
	await get_tree().process_frame
	var replacement := pool.acquire()
	_expect(is_instance_valid(replacement), "pool prunes externally freed instances")
	pool.queue_free()
	await get_tree().process_frame

	# 最早实例按最近一次 acquire 的顺序计算；被回收后会重新插入有序活跃集合末尾，
	# 成为最新活跃实例，而不是继续沿用最初创建时间。
	var recycle_pool := UFramePool.new()
	recycle_pool.pool_scene = packed
	recycle_pool.initial_size = 2
	recycle_pool.maximum_size = 2
	var recycle_events: Array[String] = []
	var release_process_states: Array[bool] = []
	var acquire_process_states: Array[bool] = []
	var release_space_states: Array[bool] = []
	var acquire_space_states: Array[bool] = []
	var created_instances: Array[Node] = []
	recycle_pool.instance_created.connect(func(instance: Node) -> void: created_instances.append(instance))
	recycle_pool.instance_released.connect(func(instance: Node) -> void:
		recycle_events.append("released")
		release_process_states.append(instance.can_process())
		release_space_states.append(PhysicsServer2D.area_get_space((instance as Area2D).get_rid()).is_valid())
	)
	recycle_pool.instance_acquired.connect(func(instance: Node) -> void:
		recycle_events.append("acquired")
		acquire_process_states.append(instance.can_process())
		acquire_space_states.append(PhysicsServer2D.area_get_space((instance as Area2D).get_rid()).is_valid())
	)
	add_child(recycle_pool)
	await get_tree().process_frame
	var oldest := recycle_pool.acquire() as Area2D
	var newer := recycle_pool.acquire() as Area2D
	recycle_events.clear()
	release_process_states.clear()
	acquire_process_states.clear()
	release_space_states.clear()
	acquire_space_states.clear()
	var recycled_oldest := recycle_pool.acquire() as Area2D
	_expect(recycled_oldest == oldest, "pool recycles the oldest current active lifecycle at capacity")
	_expect(
		recycle_events == ["released", "acquired"]
		and release_process_states == [false]
		and acquire_process_states == [true]
		and release_space_states == [false]
		and acquire_space_states == [true],
		"pool recycling runs the complete release and acquire activation lifecycle"
	)
	recycle_events.clear()
	var second_recycled := recycle_pool.acquire() as Area2D
	_expect(second_recycled == newer, "a recycled instance becomes newest before the next overflow")
	_expect(recycle_pool.get_active_count() == 2 and recycle_pool.get_total_count() == 2 and created_instances.size() == 2, "pool recycling keeps counts bounded without creating nodes")
	_expect(recycle_pool.release(recycled_oldest), "pool can normally release a recycled lifecycle")
	recycle_events.clear()
	_expect(recycle_pool.acquire() == recycled_oldest and recycle_events == ["acquired"], "pool always prefers an available instance before forced recycling")
	recycle_pool.queue_free()
	await get_tree().process_frame

	# maximum_size=0 本身就是“不启用上限”，因此始终按需扩容。
	var unlimited_pool := UFramePool.new()
	unlimited_pool.pool_scene = packed
	add_child(unlimited_pool)
	await get_tree().process_frame
	var unlimited_a := unlimited_pool.acquire()
	var unlimited_b := unlimited_pool.acquire()
	var unlimited_c := unlimited_pool.acquire()
	_expect(unlimited_a != unlimited_b and unlimited_b != unlimited_c and unlimited_pool.get_total_count() == 3, "pool grows while maximum_size is unlimited")
	unlimited_pool.queue_free()
	await get_tree().process_frame

	# 组合式实体的碰撞组件保留 Godot 默认的 Inherit + DisableMode Remove。
	# 只切换根节点处理模式，后代会自动退出和恢复物理空间。
	var composed_template := Node2D.new()
	var nested_area := Area2D.new()
	nested_area.name = "HitboxComponent"
	nested_area.collision_layer = 4
	nested_area.collision_mask = 2
	composed_template.add_child(nested_area)
	nested_area.owner = composed_template
	var nested_body := StaticBody2D.new()
	nested_body.name = "Body"
	nested_body.collision_layer = 16
	nested_body.collision_mask = 1
	composed_template.add_child(nested_body)
	nested_body.owner = composed_template
	var composed_scene := PackedScene.new()
	_expect(composed_scene.pack(composed_template) == OK, "pack composed pool fixture")
	composed_template.free()
	var composed_pool := UFramePool.new()
	composed_pool.pool_scene = composed_scene
	composed_pool.initial_size = 1
	add_child(composed_pool)
	await get_tree().process_frame
	var composed_instance := composed_pool.acquire() as Node2D
	var active_area := composed_instance.get_node("HitboxComponent") as Area2D
	var active_body := composed_instance.get_node("Body") as StaticBody2D
	_expect(
		active_area.can_process()
		and PhysicsServer2D.area_get_space(active_area.get_rid()).is_valid()
		and active_area.collision_layer == 4
		and active_area.collision_mask == 2,
		"pool activates nested Area2D through inherited processing"
	)
	_expect(
		active_body.can_process()
		and PhysicsServer2D.body_get_space(active_body.get_rid()).is_valid()
		and active_body.collision_layer == 16
		and active_body.collision_mask == 1,
		"pool activates nested physics body through inherited processing"
	)
	_expect(composed_pool.release(composed_instance), "release composed pooled entity")
	_expect(
		not active_area.can_process()
		and not PhysicsServer2D.area_get_space(active_area.get_rid()).is_valid()
		and active_area.monitoring
		and active_area.monitorable
		and active_area.collision_layer == 4
		and active_area.collision_mask == 2,
		"Godot removes idle nested Area2D while preserving its configuration"
	)
	_expect(
		not active_body.can_process()
		and not PhysicsServer2D.body_get_space(active_body.get_rid()).is_valid()
		and active_body.collision_layer == 16
		and active_body.collision_mask == 1,
		"Godot removes idle nested body while preserving its configuration"
	)
	composed_pool.queue_free()
	await get_tree().process_frame

func _test_arena_scene_composition() -> void:
	var arena_scene := load("res://examples/arena/arena_demo.tscn") as PackedScene
	var arena := arena_scene.instantiate()
	var behavior_manager := arena.get_node_or_null("World/Player/BehaviorManager") as UFrameBehaviorManager
	_expect(arena.get_node_or_null("World/Player/HealthComponent") is UFrameHealth, "arena player authors Health in scene")
	_expect(arena.get_node_or_null("World/Player/TeamComponent") is UFrameTeam, "arena player authors Team in scene")
	_expect(arena.get_node_or_null("World/Player/HurtboxComponent") is UFrameHurtbox2D, "arena player authors Hurtbox in scene")
	_expect(behavior_manager != null and behavior_manager.get_behavior(&"Movement") is ArenaPlayerMovementBehavior, "arena player groups real movement behavior under manager")
	var enemy_pool := arena.get_node_or_null("World/EnemyPool") as UFramePool
	var bullet_pool := arena.get_node_or_null("World/BulletPool") as UFramePool
	var effect_pool := arena.get_node_or_null("World/EffectPool") as UFramePool
	_expect(enemy_pool != null, "arena authors EnemyPool in scene")
	_expect(bullet_pool != null, "arena authors BulletPool in scene")
	_expect(effect_pool != null, "arena authors EffectPool in scene")
	_expect(
		enemy_pool.maximum_size == 40
		and bullet_pool.maximum_size == 64
		and effect_pool.maximum_size == 48,
		"arena configures bounded pools with automatic oldest recycling"
	)
	_expect(arena.has_node("MainCamera") and arena.has_node("HUD/TopMargin/TopRow/MainPanel"), "arena authors camera and HUD in scene")
	arena.free()
	var enemy_scene := load("res://examples/arena/arena_enemy.tscn") as PackedScene
	var enemy := enemy_scene.instantiate()
	_expect(enemy.get_node_or_null("HealthComponent") is UFrameHealth and enemy.get_node_or_null("TeamComponent") is UFrameTeam, "arena enemy authors data components")
	_expect(enemy.get_node_or_null("HurtboxComponent") is UFrameHurtbox2D and enemy.get_node_or_null("ContactHitbox") is UFrameHitbox2D, "arena enemy authors combat components")
	enemy.free()
	var bullet_scene := load("res://examples/arena/arena_bullet.tscn") as PackedScene
	var bullet := bullet_scene.instantiate()
	_expect(bullet is ArenaBullet and bullet.get_node_or_null("HitboxComponent") is UFrameHitbox2D, "arena bullet composes Hitbox under entity root")
	bullet.free()

func _test_arena_behavior_runtime() -> void:
	var player_scene := load("res://examples/arena/arena_player.tscn") as PackedScene
	var player := player_scene.instantiate() as ArenaPlayer
	player.position = Vector2(300, 300)
	add_child(player)
	var movement := player.behaviors.get_behavior(&"Movement") as ArenaPlayerMovementBehavior
	if movement == null:
		_expect(false, "arena player exposes Movement through BehaviorManager")
		player.queue_free()
		await get_tree().process_frame
		return
	var start_x := player.position.x
	Input.action_press(&"demo_move_right")
	# physics_frame 信号发生在物理回调之前；第二次信号到来时已完成一次移动。
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(&"demo_move_right")
	_expect(movement != null and player.position.x > start_x, "arena Movement behavior performs real player physics")
	_arena_dust_events = 0
	movement.dust_requested.connect(_on_arena_test_dust)
	player.position.x = player.get_viewport_rect().size.x - movement.maximum_margin.x
	Input.action_press(&"demo_move_right")
	for _index in 8:
		await get_tree().physics_frame
	Input.action_release(&"demo_move_right")
	_expect(_arena_dust_events == 0, "arena Movement behavior does not emit dust while held against boundary")
	player.queue_free()
	await get_tree().process_frame

func _on_arena_test_dust(_origin: Vector2, _movement_velocity: Vector2) -> void:
	_arena_dust_events += 1

func _test_platform_and_loot_scene_composition() -> void:
	# 示例的设计哲学也属于回归目标：静态实体与组件必须能直接在场景树中看见。
	var player_scene := load("res://examples/platformer/platformer_player.tscn") as PackedScene
	var platform_player := player_scene.instantiate()
	var machine := platform_player.get_node_or_null("StateMachine") as UFrameStateMachine
	_expect(machine != null and machine.get_parent() == platform_player, "platform state machine is a direct player component")
	_expect(machine.get_node_or_null("Idle") is Platformer_Base_State, "platform authors Idle state from the shared player state base")
	_expect(machine.get_node_or_null("Run") is Platformer_Base_State, "platform authors Run state from the shared player state base")
	_expect(machine.get_node_or_null("Air") is Platformer_Base_State, "platform authors Air state from the shared player state base")
	_expect(platform_player.has_node("CollisionShape2D") and platform_player.has_node("VisualRoot"), "platform authors collision and visuals in player scene")
	platform_player.free()

	var platform_scene := load("res://examples/platformer/platformer_demo.tscn") as PackedScene
	var platform := platform_scene.instantiate()
	var platform_effect_pool := platform.get_node_or_null("World/EffectPool") as UFramePool
	_expect(platform_effect_pool != null, "platform authors effect pool in level scene")
	_expect(platform_effect_pool.maximum_size == 32, "platform effect pool demonstrates bounded oldest recycling")
	_expect(platform.has_node("World/Ground/CollisionShape2D") and platform.has_node("World/Goal/CollisionShape2D"), "platform authors level collision in scene")
	_expect(platform.has_node("World/Player/StateMachine") and platform.has_node("HUD/TopMargin/Row/MainPanel"), "platform instances player composition and HUD")
	platform.free()

	var loot_scene := load("res://examples/loot/loot_demo.tscn") as PackedScene
	var loot := loot_scene.instantiate()
	var inventory := loot.get_node_or_null("Player/InventoryComponent") as UFrameInventory
	_expect(inventory != null and inventory.slot_count == 64, "loot authors 64-slot inventory component in scene")
	_expect(loot.has_node("MainMargin/ContentRow/InventoryPanel/InventoryColumn/GridCenter/SlotGrid"), "loot authors static UI and SlotGrid mount point")
	_expect(loot.get("loot_table") is UFrameLootTable, "loot references configured LootTable resource")
	_expect((loot.get("item_definitions") as Array).size() == 9 and loot.get("slot_scene") is PackedScene, "loot references item resources and reusable slot scene")
	loot.free()

func _test_platform_air_state_runtime() -> void:
	var world := Node2D.new()
	var floor_body := StaticBody2D.new()
	var floor_collision := CollisionShape2D.new()
	var floor_shape := RectangleShape2D.new()
	floor_shape.size = Vector2(400, 20)
	floor_collision.shape = floor_shape
	floor_body.position = Vector2(200, 220)
	floor_body.add_child(floor_collision)
	world.add_child(floor_body)

	var player_scene := load("res://examples/platformer/platformer_player.tscn") as PackedScene
	var player := player_scene.instantiate() as PlatformerPlayer
	player.position = Vector2(200, 120)
	player.controls_enabled = false
	world.add_child(player)
	add_child(world)

	var transitions: Array = []
	player.sm.state_changed.connect(
		func(previous: StringName, current: StringName) -> void:
			transitions.append([previous, current])
	)
	# physics_frame 在节点物理回调前发出；等待两次后才完成一次实际更新。
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(
		not player.is_on_floor() and player.sm.is_in_state(&"air") and transitions.is_empty(),
		"platform Air remains active during an airborne physics update"
	)
	for _frame in 90:
		await get_tree().physics_frame
		if player.is_on_floor() and player.sm.is_in_state(&"idle"):
			break
	_expect(player.is_on_floor(), "platform player reaches the authored test floor")
	_expect(
		transitions == [[&"air", &"idle"]],
		"platform Air remains active while airborne and changes to Idle only after landing"
	)

	player.position = Vector2(200, 120)
	player.velocity = Vector2.ZERO
	player.sm.change_state(&"air")
	transitions.clear()
	player.controls_enabled = true
	Input.action_press(&"demo_move_right")
	for _frame in 90:
		await get_tree().physics_frame
		if player.is_on_floor() and player.sm.is_in_state(&"run"):
			break
	Input.action_release(&"demo_move_right")
	_expect(player.is_on_floor(), "platform player reaches the test floor while moving")
	_expect(
		transitions == [[&"air", &"run"]],
		"platform Air changes to Run only after landing with horizontal input"
	)
	world.queue_free()
	await get_tree().process_frame


func _test_spider_scene_composition() -> void:
	var spider_scene := load("res://examples/spider/spider_demo.tscn") as PackedScene
	_expect(spider_scene != null, "spider example scene loads")
	if spider_scene == null:
		return
	var spider := spider_scene.instantiate()
	var tableau := spider.get_node_or_null("BoardStage/Tableau")
	var fixed_columns_valid := tableau != null and tableau.get_child_count() == SpiderGameModel.COLUMN_COUNT
	if fixed_columns_valid:
		for column_index in SpiderGameModel.COLUMN_COUNT:
			var expected_name := "Column%02d" % (column_index + 1)
			fixed_columns_valid = fixed_columns_valid and tableau.get_child(column_index).name == expected_name
	_expect(fixed_columns_valid, "spider authors all ten fixed tableau column mounts in the scene")
	_expect(
		spider.has_node("BoardStage/CardLayer")
		and spider.has_node("BoardStage/DragLayer")
		and spider.has_node("BoardStage/FeedbackOverlay"),
		"spider authors separate card, drag and feedback layers"
	)
	var difficulty_row := spider.get_node_or_null("HeaderMargin/HeaderPanel/HeaderRow/TitleBlock/DifficultyRow") as Control
	var difficulty_buttons_visible: bool = difficulty_row != null and difficulty_row.visible
	var expected_difficulty_buttons := {
		"OneSuitButton": "单色",
		"TwoSuitButton": "双色",
		"FourSuitButton": "四色",
	}
	for button_name in expected_difficulty_buttons:
		var button := difficulty_row.get_node_or_null(button_name) as Button if difficulty_row else null
		difficulty_buttons_visible = (
			difficulty_buttons_visible
			and button != null
			and button.visible
			and button.text == expected_difficulty_buttons[button_name]
		)
	_expect(difficulty_buttons_visible, "spider authors visible one-, two- and four-suit difficulty controls in the scene")
	var card_scene := spider.get("card_scene") as PackedScene
	var card_view := card_scene.instantiate() if card_scene else null
	_expect(card_view is SpiderCardView, "spider configures one reusable CardView PackedScene template")
	if card_view:
		card_view.free()
	spider.free()


func _test_spider_runtime() -> void:
	# 不只检查文件结构：实际进入树后执行一次发牌与撤销，验证模型和重复 View 的映射。
	var spider_scene := load("res://examples/spider/spider_demo.tscn") as PackedScene
	var spider := spider_scene.instantiate()
	add_child(spider)
	# 新局通过 call_deferred() 等待 Container 完成布局，因此保留两个真实帧。
	await get_tree().process_frame
	await get_tree().process_frame
	var model := spider.get("game") as SpiderGameModel
	var views := spider.get("_card_views") as Dictionary
	_expect(model != null and model.stock.size() == 50 and views.size() == 54, "spider runtime maps the initial 54 cards to reusable views")
	var first_column: Array = model.columns[0]
	var covered_view := views.get(int((first_column[0] as Dictionary).get("id", -1))) as SpiderCardView
	var top_view := views.get(int((first_column.back() as Dictionary).get("id", -1))) as SpiderCardView
	_expect(
		covered_view != null
		and float(covered_view.get("_exposed_height")) < SpiderCardView.CARD_SIZE.y
		and top_view != null
		and is_equal_approx(float(top_view.get("_exposed_height")), SpiderCardView.CARD_SIZE.y),
		"spider renders covered cards as compact strips while keeping each top card complete"
	)

	# 不可交互且未悬停的牌不应创建 0→0 Tween；这是发牌卡顿的历史回归点。
	var runtime_card_scene := spider.get("card_scene") as PackedScene
	var idle_card := runtime_card_scene.instantiate() as SpiderCardView
	add_child(idle_card)
	idle_card.interactive = false
	_expect(idle_card.get("_hover_tween") == null, "spider card skips zero-change hover tweens")
	var auto_move_requests: Array[int] = []
	idle_card.configure(777, 4, true, 0)
	idle_card.interactive = true
	idle_card.auto_move_requested.connect(func(card: SpiderCardView) -> void: auto_move_requests.append(card.card_id))
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	idle_card.call("_gui_input", right_click)
	_expect(auto_move_requests == [777], "spider card emits one auto-move intent on right-button press")
	idle_card.queue_free()
	await get_tree().process_frame

	# 通过与按钮相同的入口切换四色，确保难度不只停留在纯模型与静态场景测试中。
	spider.call("_set_busy", false)
	spider.call("_select_difficulty", 4)
	await get_tree().process_frame
	await get_tree().process_frame
	views = spider.get("_card_views") as Dictionary
	var stock_label := spider.get_node_or_null("HeaderMargin/HeaderPanel/HeaderRow/Stats/StockLabel") as Label
	_expect(
		model.suit_count == 4
		and model.stock.size() == 50
		and views.size() == 54
		and stock_label != null
		and stock_label.text.contains("四色"),
		"spider controller switches to four suits and refreshes its board and HUD"
	)
	# 等待开局的统一入场 Tween 完成，之后才能准确检查一次发牌的动画预算。
	await get_tree().create_timer(0.82).timeout

	# 初始发牌动画会短暂锁住按钮；测试显式解除表现锁，只调用与按钮相同的控制器入口。
	spider.call("_set_busy", false)
	spider.call("_on_deal_pressed")
	await get_tree().process_frame
	var active_tweens := get_tree().get_processed_tweens().size()
	_expect(active_tweens < 32, "spider deal keeps a bounded tween budget instead of animating every idle card")
	views = spider.get("_card_views") as Dictionary
	_expect(model.stock.size() == 40 and model.move_count == 1 and views.size() == 64, "spider controller deals ten cards without rebuilding fixed columns")

	spider.call("_set_busy", false)
	spider.call("_on_undo_pressed")
	await get_tree().process_frame
	views = spider.get("_card_views") as Dictionary
	_expect(model.stock.size() == 50 and model.move_count == 0 and model.score == 500 and views.size() == 54, "spider controller undo resynchronizes stock, score and card views")

	# 用真实控制器入口验证右键会移动完整的黑桃 4-3-2-A，并遵循同花色优先。
	var auto_required := _empty_spider_columns()
	var auto_source: Array = [
		_spider_suited_card(0, 4, 0, 4, true),
		_spider_suited_card(0, 3, 0, 4, true),
		_spider_suited_card(0, 2, 0, 4, true),
		_spider_suited_card(0, 1, 0, 4, true),
	]
	auto_required[0] = auto_source
	auto_required[1] = [_spider_suited_card(1, 5, 0, 4, true)]
	auto_required[2] = [_spider_suited_card(0, 5, 0, 4, true)]
	var auto_fixture := _make_spider_fixture(model, auto_required)
	if _expect_spider_restore(model, auto_fixture, "spider runtime restores right-click fixture"):
		spider.call("_sync_board", [], false, 0.0)
		await get_tree().create_timer(0.20).timeout
		views = spider.get("_card_views") as Dictionary
		var source_card_id := int((auto_source[0] as Dictionary).get("id", -1))
		var source_view := views.get(source_card_id) as SpiderCardView
		if source_view == null:
			_expect(false, "spider runtime maps the right-click source card to a view")
		else:
			spider.call("_set_busy", false)
			spider.call("_on_card_auto_move_requested", source_view)
			await get_tree().process_frame
			var moved_location := model.find_card(source_card_id)
			_expect(
				not moved_location.is_empty()
				and int(moved_location.get("column", -1)) == 2
				and model.move_count == 1
				and model.columns[2].size() >= 5,
				"spider controller right-clicks the complete sequence onto the same-suit target"
			)
	spider.queue_free()
	await get_tree().process_frame

func _test_camera() -> void:
	var service := UFrameCamera2D.new()
	add_child(service)
	var first_camera := Camera2D.new()
	first_camera.offset = Vector2(7, 3)
	first_camera.rotation_degrees = 2.0
	first_camera.add_to_group(&"main_camera")
	add_child(first_camera)
	service.set_camera(first_camera)
	service.configure_shake(Vector2(2, 2), 0.5, 100.0, 2.0)
	service.add_trauma(0.5)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(first_camera.offset == Vector2(7, 3) and is_equal_approx(first_camera.rotation_degrees, 2.0), "camera shake restores non-zero base transform")
	first_camera.queue_free()
	await get_tree().process_frame
	var second_camera := Camera2D.new()
	second_camera.add_to_group(&"main_camera")
	add_child(second_camera)
	service.add_trauma(0.1)
	_expect(service.get_camera() == second_camera, "camera service rebinds after scene camera is freed")
	service.clear_trauma()
	second_camera.queue_free()
	service.queue_free()
	await get_tree().process_frame

func _test_input() -> void:
	var service := UFrameInput.new()
	add_child(service)
	service.buffer_action(&"jump", 0.001)
	_expect(service.is_action_buffered(&"jump"), "input buffer activates")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not service.is_action_buffered(&"jump"), "input buffer expires and clears")
	service.queue_free()

func _test_transition_overlay() -> void:
	var service := UFrameTransition.new()
	add_child(service)
	await service.fade_out(0.0, Color("#345678"))
	var overlay := service.get("_overlay") as ColorRect
	_expect(overlay != null and is_equal_approx(overlay.color.a, 1.0) and overlay.color.is_equal_approx(Color("#345678")), "transition tweens actual overlay color")
	await service.fade_in(0.0, Color("#345678"))
	_expect(is_zero_approx(overlay.color.a), "transition fades back to transparent")
	service.queue_free()
	await get_tree().process_frame

func _test_state_machine() -> void:
	var owner := Node.new()
	var machine := UFrameStateMachine.new()
	machine.initial_state = &"idle"
	var early_transitions: Array = []
	var early_callback := func(previous: StringName, current: StringName) -> void:
		early_transitions.append([previous, current])
	machine.connect_state_changed(early_callback)
	machine.connect_state_changed(early_callback)
	var idle_state: StateUpdateProbe
	var run_state: StateUpdateProbe
	for state_name in [&"idle", &"run"]:
		var state := StateUpdateProbe.new()
		state.name = String(state_name)
		state.state_name = state_name
		machine.add_child(state)
		if state_name == &"idle":
			idle_state = state
		else:
			run_state = state
	owner.add_child(machine)
	add_child(owner)
	_expect(machine.is_in_state(&"idle"), "state machine enters initial state")
	_expect(
		idle_state.setup_count == 1
		and run_state.setup_count == 1
		and idle_state.setup_machine == machine
		and run_state.setup_entity == owner,
		"state machine sets up every state once with injected dependencies"
	)
	_expect(
		idle_state.lifecycle_events == ["setup", "enter"]
		and run_state.lifecycle_events == ["setup"],
		"state setup completes before the initial state enters"
	)
	_expect(
		early_transitions == [[StringName(), &"idle"]],
		"state observers connected before initialization receive initial state once"
	)
	var late_transitions: Array = []
	var late_callback := func(previous: StringName, current: StringName) -> void:
		late_transitions.append([previous, current])
	machine.connect_state_changed(late_callback)
	machine.connect_state_changed(late_callback)
	_expect(
		late_transitions == [[StringName(), &"idle"]],
		"state observers connected after initialization receive current state immediately"
	)
	# process_frame / physics_frame 信号发生在对应回调之前，因此各等待两次。
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(idle_state.update_count > 0, "state machine automatically forwards process updates")
	_expect(idle_state.physics_update_count > 0, "state machine automatically forwards physics updates")
	machine.change_state(&"run")
	_expect(machine.get_current_state_name() == &"run", "state machine changes locally")
	_expect(
		idle_state.setup_count == 1
		and run_state.setup_count == 1
		and run_state.lifecycle_events == ["setup", "enter"],
		"state transitions do not repeat one-time setup"
	)
	_expect(
		early_transitions == [[StringName(), &"idle"], [&"idle", &"run"]]
		and late_transitions == [[StringName(), &"idle"], [&"idle", &"run"]],
		"state observers continue receiving later transitions"
	)
	owner.queue_free()
	await get_tree().process_frame

func _test_behavior_lifecycle() -> void:
	var owner := Node.new()
	var manager := UFrameBehaviorManager.new()
	manager.name = "BehaviorManager"
	var behavior := LifecycleBehavior.new()
	behavior.name = "Lifecycle"
	var events := behavior.events
	manager.add_child(behavior)
	owner.add_child(manager)
	add_child(owner)
	await get_tree().process_frame
	_expect(manager.get_parent() == owner, "behavior manager stays directly under its entity")
	_expect(behavior.manager == manager and behavior.last_entered_entity == owner, "behavior receives manager and entity before on_enter")
	_expect(behavior.entered_after_entity_ready, "behavior enters only after its entity is ready")
	_expect(manager.get_behavior(&"Lifecycle") == behavior and manager.has_behavior(&"Lifecycle"), "behavior manager queries direct children by node name")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(behavior.update_count > 0, "behavior automatically forwards process updates")
	_expect(behavior.physics_update_count > 0, "behavior automatically forwards physics updates")
	_expect(manager.set_behavior_enabled(&"Lifecycle", false), "behavior manager disables a named behavior")
	_expect(behavior.enter_count == 1 and behavior.exit_count == 1, "behavior enter/disable lifecycle is paired")
	var stopped_update_count := behavior.update_count
	var stopped_physics_count := behavior.physics_update_count
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(behavior.update_count == stopped_update_count, "disabled behavior stops process updates")
	_expect(behavior.physics_update_count == stopped_physics_count, "disabled behavior stops physics updates")
	manager.remove_child(behavior)
	behavior.enabled = true
	_expect(behavior.enter_count == 1, "detached behavior does not enter outside the scene tree")
	manager.add_child(behavior)
	_expect(behavior.enter_count == 2 and behavior.last_entered_entity == owner, "reattached behavior enters again with the correct entity")
	manager.set_all_enabled(false)
	_expect(behavior.exit_count == 2, "behavior manager disables all direct behaviors")
	owner.queue_free()
	await get_tree().process_frame
	_expect(events == ["enter", "exit", "enter", "exit"], "disabled behavior does not exit twice on tree removal")

func _test_audio_volume() -> void:
	var service := UFrameAudio.new()
	add_child(service)
	# 使用一个极短的内存 WAV；AudioStreamGenerator 会启动异步 Playback，
	# 在极快退出的 headless 测试中可能晚于 ObjectDB 清理线程释放，形成伪泄漏警告。
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 8000
	stream.data = PackedByteArray([128, 128, 128, 128, 128, 128, 128, 128])
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = 8
	service.play_bgm(stream, 0.0)
	service.bgm_volume = 0.5
	var player := service.get("_bgm_player") as AudioStreamPlayer
	_expect(player != null and is_equal_approx(player.volume_db, linear_to_db(0.5)), "BGM volume changes after playback starts")
	service.muted = true
	_expect(player.volume_db <= -79.0, "BGM mute applies immediately")
	service.stop_bgm()
	_expect(player.stream == null, "stopping BGM releases stream playback")
	service.queue_free()
	await get_tree().process_frame
	# AudioServer 在独立线程回收 Playback，给它一个很短的真实时间窗口。
	await get_tree().create_timer(0.05).timeout

func _test_save_recovery() -> void:
	var service := UFrameSave.new()
	var data := UFrameRunData.new()
	data.custom_data = {"score": 99}
	_expect(service.save(data, "uframe_test"), "atomic resource save")
	var main_path := "user://saves/uframe_test.tres"
	var backup_path := "user://saves/uframe_test.bak.tres"
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	_expect(DirAccess.rename_absolute(main_path, backup_path) == OK, "simulate interrupted save window")
	var loaded := service.load("uframe_test") as UFrameRunData
	_expect(loaded != null and loaded.custom_data.get("score") == 99, "load restores backup after interrupted replacement")
	_expect(FileAccess.file_exists(main_path), "backup is promoted to main save")
	_expect(service.delete("uframe_test"), "save delete removes recovery family")
	service.free()

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("TEST: %s" % message)
