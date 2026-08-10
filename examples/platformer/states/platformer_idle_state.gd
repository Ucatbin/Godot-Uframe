extends Platformer_Base_State

## 平台跳跃待机状态
##
## 负责玩家在地面待机时减速、响应跳跃，以及切换到 Run / Air 状态
## 状态节点会直接驱动物理移动，不只是用于标记当前状态

#region 状态回调
func on_enter(_data := {}) -> void:
	# 清除上一轮奔跑累计的脚步距离
	if player:
		player.reset_walk_feedback()

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

	player.move_and_slide()
	if not player.is_on_floor():
		state_machine.change_state(&"air")
	elif not is_zero_approx(player.move_axis):
		state_machine.change_state(&"run")
#endregion
