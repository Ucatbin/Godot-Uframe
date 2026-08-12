extends Node

## Pool 生命周期重入回归使用的最小实例。
##
## 分别在 ready、取出钩子与归还钩子中尝试同步 acquire，用于确认 Pool 会拒绝
## 尚未完成的同池生命周期事务；本脚本只用于测试，不属于插件运行时。

#region 观测状态
var ready_attempt_count := 0
var acquire_hook_count := 0
var release_hook_count := 0
var ready_acquire_result: Node
var acquire_hook_result: Node
var release_hook_result: Node
#endregion

#region 生命周期与对象池钩子
func _ready() -> void:
	ready_attempt_count += 1
	var pool := get_parent() as UFramePool
	if pool:
		ready_acquire_result = pool.acquire()

func _on_pool_acquire() -> void:
	acquire_hook_count += 1
	var pool := get_parent() as UFramePool
	if pool:
		acquire_hook_result = pool.acquire()

func _on_pool_release() -> void:
	release_hook_count += 1
	var pool := get_parent() as UFramePool
	if pool:
		release_hook_result = pool.acquire()
#endregion
