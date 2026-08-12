extends Node2D

## 对象池性能测试使用的最小生命周期实例。
##
## 只记录取出与归还次数，不创建视觉、物理或计时节点，避免把业务场景成本
## 混入 UFramePool 自身的容器与生命周期调度结果。

#region 运行时状态
## 成功进入新取出生命周期的次数。
var acquire_count := 0

## 成功结束取出生命周期的次数。
var release_count := 0
#endregion

#region 对象池回调
## UFramePool 激活实例后调用。
func _on_pool_acquire() -> void:
	acquire_count += 1

## UFramePool 停用实例前调用。
func _on_pool_release() -> void:
	release_count += 1
#endregion
