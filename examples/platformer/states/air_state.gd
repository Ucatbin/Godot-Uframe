extends UFrameState

## 空中状态：负责空中操控、土狼跳、可变跳高、重力、落地与状态转换。

func on_enter(_data := {}) -> void:
	var player := entity as PlatformerPlayer
	if player:
		player.reset_walk_feedback()

func on_physics_update(delta: float) -> void:
	var player := entity as PlatformerPlayer
	if player == null:
		return

	player.velocity.x = move_toward(player.velocity.x, player.move_axis * player.movement_speed, player.air_acceleration * delta)
	var started_jump := false
	if player.can_start_jump():
		player.begin_jump()
		started_jump = true
	if not started_jump:
		var holding_jump := player.jump_held and player.velocity.y < 0.0 and player.jump_hold_remaining > 0.0
		player.velocity.y += player.gravity * (0.45 if holding_jump else 1.0) * delta
		if player.jump_released and player.velocity.y < player.jump_cut_speed:
			player.velocity.y = player.jump_cut_speed

	var was_on_floor := player.is_on_floor()
	var vertical_speed_before_move := player.velocity.y
	player.move_and_slide()
	if not was_on_floor and player.is_on_floor():
		if vertical_speed_before_move > 0.0:
			player.emit_land_feedback(vertical_speed_before_move)
		if is_zero_approx(player.move_axis):
			state_machine.change_state(&"idle")
		else:
			state_machine.change_state(&"run")
