extends RefCounted

## 蜘蛛纸牌的纯规则模型，支持单花色、双花色与四花色三种标准难度。
##
## 本类不继承 Node，也不认识卡牌 View、Tween 或鼠标输入。因此它可以用
## [code].new()[/code] 独立测试；spider_demo.tscn 只负责把数组状态显示成可拖动的卡牌。
##
## 卡牌使用轻量 Dictionary：
## `{ "id": 唯一编号, "rank": 1 到 13, "suit": 0 到 3, "face_up": 是否翻开 }`。
## 其中 1 是 A，11/12/13 分别是 J/Q/K。
##
## 花色只用整数保存，避免模型依赖任何贴图或文字：0/1/2/3 分别由 View 决定
## 显示成哪一种图案。难度为 1 时只使用 0；难度为 2 时使用 0、1；四花色全部使用。
class_name SpiderGameModel

#region 规则常量
const COLUMN_COUNT := 10
const CARDS_PER_RUN := 13
const TOTAL_RUNS := 8
const STOCK_DEAL_SIZE := 10
const INITIAL_SCORE := 500
const VALID_SUIT_COUNTS := [1, 2, 4]
## 快照撤销最容易读懂且只有 104 张牌；仍设置上限，避免超长挂机牌局无限占用内存。
const MAX_UNDO_STEPS := 256
#endregion

#region 牌局状态
## 十个纵列。列内顺序从底牌到顶牌，数组末尾就是玩家看到的最上方卡牌。
var columns: Array[Array] = []
## 尚未发出的牌；每次从数组末尾取十张，依次放到十列顶部。
var stock: Array[Dictionary] = []
## 已经收齐并移出桌面的同花色 K 到 A 组数。
var completed_runs := 0
## 当前牌局已经提交的移动与发牌次数。
var move_count := 0
## 当前分数；移动会扣分，完成整组会加分。
var score := INITIAL_SCORE
## 当前牌局使用的花色数量。请通过 [method new_game] 切换难度，不要在牌局中途直接改写。
var suit_count := 1

var _history: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
#endregion

#region 牌局创建
## 建立一局标准蜘蛛纸牌。传入 0 或其他非负 seed 可稳定复现；-1 表示随机。
## [param suit_count_value] 只接受 1、2、4；非法值回退为单花色，保证模型不会进入半合法状态。
func new_game(seed_value: int = -1, suit_count_value: int = 1) -> void:
	columns.clear()
	stock.clear()
	_history.clear()
	completed_runs = 0
	move_count = 0
	score = INITIAL_SCORE
	if not suit_count_value in VALID_SUIT_COUNTS:
		push_warning("[SpiderGameModel] suit_count 只支持 1、2、4，已回退为单花色")
		suit_count = 1
	else:
		suit_count = int(suit_count_value)

	for _column_index in COLUMN_COUNT:
		columns.append([])

	var resolved_seed := int(seed_value)
	if resolved_seed < 0:
		resolved_seed = int(Time.get_ticks_usec())
	_rng.seed = resolved_seed

	# 总牌数始终是 104。难度只改变每种花色的副本数：1×8、2×4 或 4×2。
	# ID 按“花色 -> 副本 -> 点数”生成，所以存档验证可以由 ID 反查应有花色和点数。
	var deck: Array[Dictionary] = []
	var next_id := 0
	var copies_per_suit := TOTAL_RUNS / suit_count
	for suit_value in suit_count:
		for _copy_index in copies_per_suit:
			for rank_value in range(1, CARDS_PER_RUN + 1):
				deck.append({
					"id": next_id,
					"rank": rank_value,
					"suit": suit_value,
					"face_up": false,
				})
				next_id += 1
	_shuffle(deck)

	# 标准布局：前四列六张，后六列五张，共 54 张；每列只有顶牌翻开。
	for column_index in COLUMN_COUNT:
		var card_count := 6 if column_index < 4 else 5
		for _card_index in card_count:
			columns[column_index].append(deck.pop_back())
		columns[column_index].back()["face_up"] = true

	# 剩余 50 张就是五次发牌。复制引用没有必要，牌 Dictionary 已各自唯一。
	stock.assign(deck)
#endregion

#region 移动与发牌
## 判断从某列的 start_index 开始，到该列顶部的整组牌能否移到目标列。
func can_move(from_column: int, start_index: int, to_column: int) -> bool:
	return _move_error(from_column, start_index, to_column).is_empty()

## 执行一次拖牌。失败不会改变模型；成功会保存完整快照供 [method undo] 恢复。
func move_stack(from_column: int, start_index: int, to_column: int) -> Dictionary:
	var reason := _move_error(from_column, start_index, to_column)
	if not reason.is_empty():
		return _result(false, reason)

	_push_history()
	var source := columns[from_column]
	var target := columns[to_column]
	var moved_cards: Array[Dictionary] = []
	var moved_ids: Array[int] = []
	for index in range(start_index, source.size()):
		var card := source[index] as Dictionary
		moved_cards.append(card)
		moved_ids.append(int(card["id"]))
	source.resize(start_index)
	target.append_array(moved_cards)

	move_count += 1
	score = maxi(score - 1, 0)
	var flipped_ids: Array[int] = []
	var removed_ids: Array[int] = []
	_flip_exposed_card(source, flipped_ids)
	# 移走牌组和放下牌组都可能形成新的 K 到 A，因此两边都检查。
	_collect_completed_runs(from_column, flipped_ids, removed_ids)
	_collect_completed_runs(to_column, flipped_ids, removed_ids)
	var completed_delta := removed_ids.size() / CARDS_PER_RUN

	return _result(true, "", moved_ids, flipped_ids, removed_ids, completed_delta)

## 只有库存足够且十列都非空时才能发牌，这是标准蜘蛛纸牌的重要限制。
func can_deal() -> bool:
	if stock.size() < STOCK_DEAL_SIZE or is_won():
		return false
	for column in columns:
		if column.is_empty():
			return false
	return true

## 向十列各发一张正面牌，并检查发牌后是否出现完整序列。
func deal_stock() -> Dictionary:
	if stock.size() < STOCK_DEAL_SIZE:
		return _result(false, "no_stock")
	for column in columns:
		if column.is_empty():
			return _result(false, "empty_column")
	if is_won():
		return _result(false, "already_won")

	_push_history()
	var dealt_ids: Array[int] = []
	for column_index in COLUMN_COUNT:
		var card := stock.pop_back() as Dictionary
		card["face_up"] = true
		columns[column_index].append(card)
		dealt_ids.append(int(card["id"]))

	move_count += 1
	score = maxi(score - 1, 0)
	var flipped_ids: Array[int] = []
	var removed_ids: Array[int] = []
	for column_index in COLUMN_COUNT:
		_collect_completed_runs(column_index, flipped_ids, removed_ids)
	var completed_delta := removed_ids.size() / CARDS_PER_RUN
	return _result(true, "", dealt_ids, flipped_ids, removed_ids, completed_delta)
#endregion

#region 撤销
## 是否存在可以恢复的动作快照。
func can_undo() -> bool:
	return not _history.is_empty()

## 撤销严格恢复动作前的列、库存、翻面、完成数、步数和分数。
func undo() -> Dictionary:
	if _history.is_empty():
		return _result(false, "no_history")
	var previous_state := _history.pop_back() as Dictionary
	_apply_state(previous_state)
	return _result(true, "")
#endregion

#region 规则查询
## 八组同花色 K 到 A 全部收齐后返回 true。
func is_won() -> bool:
	return completed_runs >= TOTAL_RUNS

## 返回库存仍可向十列发牌的次数。
func get_stock_deals_remaining() -> int:
	return stock.size() / STOCK_DEAL_SIZE

## 返回某张唯一 ID 的位置，供薄控制器把 View 映射回规则模型。
func find_card(card_id: int) -> Dictionary:
	for column_index in columns.size():
		for card_index in columns[column_index].size():
			if int(columns[column_index][card_index].get("id", -1)) == card_id:
				return {"column": column_index, "index": card_index}
	return {}

## 公开这个查询是为了提示与拖拽起点检查；它不会改变任何状态。
func is_movable_sequence(column_index: int, start_index: int) -> bool:
	if column_index < 0 or column_index >= columns.size():
		return false
	var column := columns[column_index]
	if start_index < 0 or start_index >= column.size():
		return false
	if not bool(column[start_index].get("face_up", false)):
		return false
	for index in range(start_index, column.size() - 1):
		var lower := column[index] as Dictionary
		var upper := column[index + 1] as Dictionary
		if not bool(upper.get("face_up", false)):
			return false
		if int(lower.get("rank", 0)) != int(upper.get("rank", 0)) + 1:
			return false
		# 多花色规则中，点数相连但花色不同的牌不能作为一整个后缀移动。
		if int(lower.get("suit", -1)) != int(upper.get("suit", -1)):
			return false
	return true

## 为右键自动移动寻找一个确定的目标列，不修改牌局状态。
##
## 优先级符合常见蜘蛛纸牌操作：
## 1. 接到点数大 1 且与所移动牌组同花色的顶牌；
## 2. 没有同花目标时，接到其他花色但点数大 1 的顶牌；
## 3. 完全没有点数目标时，才使用第一个空列。
##
## 多张牌仍必须是 [method is_movable_sequence] 认可的同花色连续后缀。
## 返回 -1 表示没有合法目标。
func find_auto_move_target(from_column: int, start_index: int) -> int:
	if not is_movable_sequence(from_column, start_index):
		return -1
	var moving_card := columns[from_column][start_index] as Dictionary
	var moving_suit := int(moving_card.get("suit", -1))
	var other_suit_target := -1
	var empty_target := -1
	for target_column in columns.size():
		if target_column == from_column or not can_move(from_column, start_index, target_column):
			continue
		var target := columns[target_column]
		if target.is_empty():
			if empty_target < 0:
				empty_target = target_column
			continue
		var target_top := target.back() as Dictionary
		if int(target_top.get("suit", -1)) == moving_suit:
			return target_column
		if other_suit_target < 0:
			other_suit_target = target_column
	return other_suit_target if other_suit_target >= 0 else empty_target
#endregion

#region 快照
## 快照只保存玩法数据，不包含撤销栈本身，避免历史呈指数增长。
func capture_state() -> Dictionary:
	return {
		"columns": columns.duplicate(true),
		"stock": stock.duplicate(true),
		"completed_runs": completed_runs,
		"move_count": move_count,
		"score": score,
		"suit_count": suit_count,
	}

## 测试、存档或调试工具可以恢复状态。返回 false 表示数据结构不合法。
## 正常恢复会清空旧撤销历史，因为旧历史属于另一条时间线。
func restore_state(state: Dictionary) -> bool:
	if not _is_valid_state(state):
		return false
	_apply_state(state)
	_history.clear()
	return true
#endregion

#region 移动内部实现
func _move_error(from_column: int, start_index: int, to_column: int) -> String:
	if from_column < 0 or from_column >= columns.size():
		return "invalid_source"
	if to_column < 0 or to_column >= columns.size():
		return "invalid_target"
	if from_column == to_column:
		return "same_column"
	if not is_movable_sequence(from_column, start_index):
		return "broken_sequence"
	var moving_card := columns[from_column][start_index] as Dictionary
	var target := columns[to_column]
	if target.is_empty():
		return ""
	var target_top := target.back() as Dictionary
	if int(target_top.get("rank", 0)) != int(moving_card.get("rank", 0)) + 1:
		return "rank_mismatch"
	return ""

func _push_history() -> void:
	_history.append(capture_state())
	if _history.size() > MAX_UNDO_STEPS:
		_history.pop_front()

func _flip_exposed_card(column: Array, flipped_ids: Array[int]) -> void:
	if column.is_empty():
		return
	var top := column.back() as Dictionary
	if bool(top.get("face_up", false)):
		return
	top["face_up"] = true
	flipped_ids.append(int(top.get("id", -1)))

func _collect_completed_runs(column_index: int, flipped_ids: Array[int], removed_ids: Array[int]) -> void:
	var column := columns[column_index]
	while _has_complete_run(column):
		var one_run: Array[int] = []
		# pop_back() 得到 A、2……K；反转后提供更适合视觉编排的 K 到 A 顺序。
		for _card_index in CARDS_PER_RUN:
			var removed := column.pop_back() as Dictionary
			one_run.append(int(removed.get("id", -1)))
		one_run.reverse()
		removed_ids.append_array(one_run)
		completed_runs += 1
		score += 100
		_flip_exposed_card(column, flipped_ids)

func _has_complete_run(column: Array) -> bool:
	if column.size() < CARDS_PER_RUN:
		return false
	var start := column.size() - CARDS_PER_RUN
	var run_suit := int((column[start] as Dictionary).get("suit", -1))
	for offset in CARDS_PER_RUN:
		var card := column[start + offset] as Dictionary
		if not bool(card.get("face_up", false)):
			return false
		if int(card.get("rank", 0)) != CARDS_PER_RUN - offset:
			return false
		if int(card.get("suit", -1)) != run_suit:
			return false
	return true
#endregion

#region 状态恢复与校验
func _apply_state(state: Dictionary) -> void:
	columns.clear()
	for saved_column in state.get("columns", []):
		columns.append((saved_column as Array).duplicate(true))
	stock.assign((state.get("stock", []) as Array).duplicate(true))
	completed_runs = int(state.get("completed_runs", 0))
	move_count = int(state.get("move_count", 0))
	score = int(state.get("score", INITIAL_SCORE))
	suit_count = int(state.get("suit_count", 1))

func _is_valid_state(state: Dictionary) -> bool:
	if not state.has("suit_count") or typeof(state["suit_count"]) != TYPE_INT:
		return false
	var saved_suit_count := int(state["suit_count"])
	if not saved_suit_count in VALID_SUIT_COUNTS:
		return false
	var saved_columns := state.get("columns") as Array
	var saved_stock := state.get("stock") as Array
	if saved_columns == null or saved_columns.size() != COLUMN_COUNT or saved_stock == null:
		return false
	var seen_ids: Dictionary = {}
	var card_count := 0
	for column in saved_columns:
		if not column is Array:
			return false
		var reached_face_up_cards := false
		for card in column:
			if not _is_valid_card(card, saved_suit_count):
				return false
			var is_face_up := bool((card as Dictionary).get("face_up", false))
			if is_face_up:
				reached_face_up_cards = true
			elif reached_face_up_cards:
				# 可达牌列只能是“暗牌前缀 + 明牌后缀”，不能把暗牌夹在明牌上方。
				return false
			var card_id := int((card as Dictionary).get("id", -1))
			if seen_ids.has(card_id):
				return false
			seen_ids[card_id] = true
			card_count += 1
		if not (column as Array).is_empty() and not bool((column as Array).back().get("face_up", false)):
			return false
	if saved_stock.size() > 50 or saved_stock.size() % STOCK_DEAL_SIZE != 0:
		return false
	for card in saved_stock:
		if not _is_valid_card(card, saved_suit_count):
			return false
		if bool((card as Dictionary).get("face_up", false)):
			return false
		var stock_card_id := int((card as Dictionary).get("id", -1))
		if seen_ids.has(stock_card_id):
			return false
		seen_ids[stock_card_id] = true
		card_count += 1
	var saved_completed := int(state.get("completed_runs", 0))
	if (
		saved_completed < 0
		or saved_completed > TOTAL_RUNS
		or card_count + saved_completed * CARDS_PER_RUN != TOTAL_RUNS * CARDS_PER_RUN
		or int(state.get("move_count", 0)) < 0
		or int(state.get("score", INITIAL_SCORE)) < 0
	):
		return false

	# 仅检查“有 104 个不同 ID”仍不够：伪造状态可能删掉十三张同点数牌，再谎称完成了一组。
	# ID 的固定编码让我们能计算每个花色、每个点数缺少多少张。合法的已收组必须让同一
	# 花色的 A 到 K 各缺少相同数量，所有花色缺失组数之和也必须等于 completed_runs。
	var copies_per_suit := TOTAL_RUNS / saved_suit_count
	var inferred_completed_runs := 0
	for suit_value in saved_suit_count:
		var missing_per_rank := -1
		for rank_value in range(1, CARDS_PER_RUN + 1):
			var present_count := 0
			for copy_index in copies_per_suit:
				var expected_id := (
					(suit_value * copies_per_suit + copy_index) * CARDS_PER_RUN
					+ rank_value - 1
				)
				if seen_ids.has(expected_id):
					present_count += 1
			var missing_count := copies_per_suit - present_count
			if missing_per_rank < 0:
				missing_per_rank = missing_count
			elif missing_count != missing_per_rank:
				return false
		inferred_completed_runs += missing_per_rank
	return inferred_completed_runs == saved_completed

func _is_valid_card(value: Variant, expected_suit_count: int) -> bool:
	if not value is Dictionary:
		return false
	var card := value as Dictionary
	var rank_value := int(card.get("rank", 0))
	var card_id := int(card.get("id", -1))
	var suit_value := int(card.get("suit", -1))
	var copies_per_suit := TOTAL_RUNS / expected_suit_count
	var expected_suit := card_id / (copies_per_suit * CARDS_PER_RUN)
	return (
		card_id >= 0
		and card_id < TOTAL_RUNS * CARDS_PER_RUN
		and rank_value == card_id % CARDS_PER_RUN + 1
		and card.has("suit")
		and typeof(card["suit"]) == TYPE_INT
		and suit_value >= 0
		and suit_value < expected_suit_count
		and suit_value == expected_suit
		and card.has("face_up")
		and typeof(card["face_up"]) == TYPE_BOOL
	)
#endregion

#region 内部工具
func _shuffle(deck: Array[Dictionary]) -> void:
	for index in range(deck.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var temporary := deck[index]
		deck[index] = deck[swap_index]
		deck[swap_index] = temporary

func _result(
	succeeded: bool,
	reason: String,
	moved_ids: Array[int] = [],
	flipped_ids: Array[int] = [],
	removed_ids: Array[int] = [],
	completed_delta: int = 0
) -> Dictionary:
	return {
		"success": succeeded,
		"reason": reason,
		"moved_ids": moved_ids,
		"flipped_ids": flipped_ids,
		"removed_ids": removed_ids,
		"completed_delta": completed_delta,
	}
#endregion
