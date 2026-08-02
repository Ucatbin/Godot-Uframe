extends Node

## 场景过渡集成测试入口。模拟示例启动器在旧场景中发起过渡。
## 传入 --arena、--platformer、--loot 或 --spider，可以把对应示例作为真实目标场景；
## 不传目标参数时仍使用最小测试场景，--async 只负责切换加载方式。

const TransitionProbe := preload("res://tests/scene_transition_probe.gd")

func _ready() -> void:
	var arguments := OS.get_cmdline_user_args()
	var probe := TransitionProbe.new()
	probe.target_path = "res://tests/scene_transition_target.tscn"
	if "--arena" in arguments:
		probe.target_path = "res://examples/arena/arena_demo.tscn"
	elif "--platformer" in arguments:
		probe.target_path = "res://examples/platformer/platformer_demo.tscn"
	elif "--loot" in arguments:
		probe.target_path = "res://examples/loot/loot_demo.tscn"
	elif "--spider" in arguments:
		probe.target_path = "res://examples/spider/spider_demo.tscn"
	probe.asynchronous = "--async" in arguments
	UFrame.add_child(probe)
	probe.run.call_deferred()
