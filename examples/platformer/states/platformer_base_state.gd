class_name Platformer_Base_State
extends UFrameState

## 平台跳跃状态基类
##
## 在状态机装配阶段统一缓存强类型玩家引用，避免各状态在每个物理帧重复转换

## 所属平台玩家；由 [method UFrameState.on_setup] 阶段设置一次
var player: PlatformerPlayer

func on_setup() -> void:
	player = entity as PlatformerPlayer
	if player == null:
		push_error("[Platformer_Base_State] %s 必须属于 PlatformerPlayer" % state_name)
