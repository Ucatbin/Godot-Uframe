extends Node

## UFrame 插件全局入口
##
## 启用插件后会自动注册为 Autoload，不需要手动挂到场景中。
## 本脚本只创建 EventBus 和已启用的全局服务，不负责实体组件或玩法对象的装配。
## 可选模块由“项目设置 → UFrame → Modules”控制，关闭后对应引用为 [code]null[/code]。
##
## 使用示例：
## [codeblock]
## UFrame.events.publish(&"game_started")
## UFrame.audio.play_sfx(click_sound)
## [/codeblock]

#region 常量
## 框架版本，可用于调试信息或兼容性检查。
const VERSION := "0.4.0"
#endregion

#region 信号
## 全局入口与所有已启用模块完成创建后发出。
signal ready_completed
#endregion

#region 运行时状态
## 始终启用的低频跨系统事件总线。
var events: UFrameEventBus

## 通过内容类型和唯一 ID 管理运行时数据的可选注册表。
var registry: UFrameRegistry

## 负责 [Resource] 保存、读取和删除的可选服务。
var save: UFrameSave

## 负责 BGM 与非空间音效播放器复用的可选服务。
var audio: UFrameAudio

## 负责主场景切换和叠加场景管理的可选服务。
var scenes: UFrameSceneService

## 负责淡入、淡出和带遮罩场景切换的可选服务。
var transitions: UFrameTransition

## 默认关闭的输入缓冲服务，动作游戏需要时再启用。
var input: UFrameInput

## 默认关闭的 2D 相机震动服务，需要屏幕震动时再启用。
var camera: UFrameCamera2D
#endregion

#region 生命周期
func _ready() -> void:
	# EventBus 体积很小，并为低频跨系统通知提供统一入口，因此始终创建
	events = UFrameEventBus.new()
	events.name = "Events"
	add_child(events)
	registry = _create_module("uframe/modules/registry", UFrameRegistry, "Registry")
	save = _create_module("uframe/modules/save", UFrameSave, "Save")
	audio = _create_module("uframe/modules/audio", UFrameAudio, "Audio")
	scenes = _create_module("uframe/modules/scene", UFrameSceneService, "Scenes")
	transitions = _create_module("uframe/modules/transition", UFrameTransition, "Transitions")
	input = _create_module("uframe/modules/input", UFrameInput, "Input")
	camera = _create_module("uframe/modules/camera", UFrameCamera2D, "Camera")
	if transitions:
		transitions.scene_service = scenes
	if ProjectSettings.get_setting("uframe/debug/logging", false):
		print("[UFrame] v%s ready" % VERSION)
	ready_completed.emit()
#endregion

#region 查询方法
## 判断模块设置是否启用。 [br][br]
## [param module_name] : 不含设置路径前缀的模块名
func is_module_enabled(module_name: String) -> bool:
	return ProjectSettings.get_setting("uframe/modules/%s" % module_name, false)
#endregion

#region 内部方法
## 根据项目设置创建可选模块；设置关闭时返回 [code]null[/code]。 [br][br]
## [param setting] : 完整的项目设置键 [br]
## [param script] : 模块脚本 [br]
## [param node_name] : 创建后的节点名
func _create_module(setting: String, script: GDScript, node_name: StringName) -> Node:
	if not ProjectSettings.get_setting(setting, false):
		return null
	var module := script.new() as Node
	module.name = node_name
	add_child(module)
	return module
#endregion
