extends Platformer_Base_State

## 平台跳跃奔跑状态
##
## 负责玩家在地面加速、根据实际位移生成脚步反馈，以及切换到 Idle / Air 状态

#region 状态回调
## 依次处理意外离地、地面移动、缓冲跳跃、脚步反馈与状态切换
func on_physics_update(delta: float) -> void:
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

	# 移动前的位置，用于按照本帧的实际位移生成脚步粒子
	var previous_position := player.global_position
	player.move_and_slide()
	player.update_walk_feedback(previous_position)
	if not player.is_on_floor():
		state_machine.change_state(&"air")
	elif is_zero_approx(player.move_axis):
		state_machine.change_state(&"idle")
#endregion
