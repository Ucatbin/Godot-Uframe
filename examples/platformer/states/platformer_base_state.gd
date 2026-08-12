extends UFrameState

## 平台跳跃状态基类。
##
## 在状态机装配阶段统一缓存强类型玩家引用，避免各状态在每个物理帧重复转换。
## 打开 platformer_player.tscn 可以查看本基类的 Idle、Run 与 Air 子类组合。
class_name PlatformerBaseState

#region 依赖
## 所属平台玩家；由 [method UFrameState.on_setup] 阶段设置一次。
var player: PlatformerPlayer
#endregion

#region 状态装配
## 状态机收集全部直属状态后调用一次；类型不匹配时保留空引用并给出诊断。
func on_setup() -> void:
	player = entity as PlatformerPlayer
	if player == null:
		push_error("[PlatformerBaseState] %s 必须属于 PlatformerPlayer" % state_name)
#endregion
