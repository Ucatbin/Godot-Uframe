extends UFrameState

## 平台跳跃空中状态
##
## 负责玩家的空中操控、土狼跳、可变跳高、重力、落地反馈与状态切换

#region 状态回调
func on_enter(_data := {}) -> void:
	# 状态机注入的玩家实体
	var player := entity as PlatformerPlayer
	# 进入空中状态时清除上一轮奔跑累计的脚步距离
	if player:
		player.reset_walk_feedback()

## 当前状态激活时由状态机在每个物理帧调用
##
## 依次处理空中移动、跳跃高度、重力、落地反馈与状态切换
func on_physics_update(delta: float) -> void:
	# 状态机注入的玩家实体
	var player := entity as PlatformerPlayer
	if player == null:
		return

	player.velocity.x = move_toward(player.velocity.x, player.move_axis * player.movement_speed, player.air_acceleration * delta)
	# 本帧是否通过土狼时间或输入缓冲开始了跳跃
	var started_jump := false
	if player.can_start_jump():
		player.begin_jump()
		started_jump = true
	if not started_jump:
		# 是否仍在长按跳跃窗口内；成立时使用较弱重力来形成高跳
		var holding_jump := player.jump_held and player.velocity.y < 0.0 and player.jump_hold_remaining > 0.0
		player.velocity.y += player.gravity * (0.45 if holding_jump else 1.0) * delta
		if player.jump_released and player.velocity.y < player.jump_cut_speed:
			player.velocity.y = player.jump_cut_speed

	# 移动前是否已经着地，用于只在本帧首次接触地面时结算落地
	var was_on_floor := player.is_on_floor()
	# 移动前的垂直速度；move_and_slide() 可能会在碰撞后修改 velocity
	var vertical_speed_before_move := player.velocity.y
	player.move_and_slide()
	if not was_on_floor and player.is_on_floor():
		if vertical_speed_before_move > 0.0:
			player.emit_land_feedback(vertical_speed_before_move)
		if is_zero_approx(player.move_axis):
			state_machine.change_state(&"idle")
		else:
			state_machine.change_state(&"run")
#endregion
