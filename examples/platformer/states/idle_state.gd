extends UFrameState

## 待机状态：负责地面减速、起跳以及 Idle → Run / Air 转换。
## 状态脚本直接驱动物理，节点并不是只用于显示当前状态。

func on_enter(_data := {}) -> void:
	var player := entity as PlatformerPlayer
	if player:
		player.reset_walk_feedback()

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

	player.move_and_slide()
	if not player.is_on_floor():
		state_machine.change_state(&"air")
	elif not is_zero_approx(player.move_axis):
		state_machine.change_state(&"run")
