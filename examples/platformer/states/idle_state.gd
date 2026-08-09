extends UFrameState

## 平台跳跃待机状态
##
## 负责玩家在地面待机时减速、响应跳跃，以及切换到 Run / Air 状态
## 状态节点会直接驱动物理移动，不只是用于标记当前状态

#region 状态回调
## 进入待机状态时清除上一轮奔跑累计的脚步距离
func on_enter(_data := {}) -> void:
	# 状态机注入的玩家实体
	var player := entity as PlatformerPlayer
	if player:
		player.reset_walk_feedback()

## 当前状态激活时由状态机在每个物理帧调用
##
## 依次处理意外离地、地面减速、缓冲跳跃与状态切换
func on_physics_update(delta: float) -> void:
	# 状态机注入的玩家实体
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
#endregion
