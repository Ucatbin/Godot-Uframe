extends UFrameState

## 奔跑状态：负责地面加速、真实位移脚步和 Run → Idle / Air 转换。

func on_physics_update(delta: float) -> void:
	var player := entity as PlatformerPlayer
	if player == null:
		return
	if not player.is_on_floor():
		state_machine.change_state(&"air")
		return

	player.velocity.x = move_toward(player.velocity.x, player.move_axis * player.movement_speed, player.ground_acceleration * delta)
	if player.can_start_jump():
		player.begin_jump()
		player.move_and_slide()
		state_machine.change_state(&"air")
		return

	var previous_position := player.global_position
	player.move_and_slide()
	player.update_walk_feedback(previous_position)
	if not player.is_on_floor():
		state_machine.change_state(&"air")
	elif is_zero_approx(player.move_axis):
		state_machine.change_state(&"idle")
