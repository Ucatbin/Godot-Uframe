extends Node

## UFrame 插件的全局入口。
##
## 启用插件后会自动以 Autoload 的方式加载，不需要手动把它挂到场景中。
## 所有全局模块都从这里访问，例如：[br]
## [codeblock]
## UFrame.events.emit_event(&"game_started")
## UFrame.audio.play_sfx(click_sound)
## [/codeblock]
## 模块可以在“项目设置 → UFrame → Modules”中开关。
## 被关闭的可选模块值为 [code]null[/code]，使用前应先判断是否存在。

## 当前框架版本。可用于调试信息或存档兼容检查。
const VERSION := "0.4.0"

## UFrame 与所有启用模块初始化完成后发出。
signal ready_completed

## 跨系统事件总线。该模块始终启用。
var events: UFrameEventBus
## 数据注册表。用于通过类型和唯一 ID 管理游戏数据。
var registry: UFrameRegistry
## 存档服务。负责 Resource 的保存、读取和删除。
var save: UFrameSave
## 音频服务。负责 BGM 与音效播放器复用。
var audio: UFrameAudio
## 场景服务。负责场景切换和附加场景。
var scenes: UFrameSceneService
## 画面过渡服务。负责淡入、淡出和带过渡的场景切换。
var transitions: UFrameTransition
## 输入缓冲服务。默认关闭，动作游戏需要时再启用。
var input: UFrameInput
## 2D 相机效果服务。默认关闭，需要屏幕震动时再启用。
var camera: UFrameCamera2D

func _ready() -> void:
	# EventBus 很小且是组件之间的基础通信设施，因此始终创建。
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

## 根据项目设置创建一个可选模块。
## 返回 null 表示开发者在项目设置中关闭了该模块。
func _create_module(setting: String, script: GDScript, node_name: StringName) -> Node:
	if not ProjectSettings.get_setting(setting, false):
		return null
	var module := script.new() as Node
	module.name = node_name
	add_child(module)
	return module

## 查询指定模块是否在项目设置中启用。
## 示例：[code]UFrame.is_module_enabled("audio")[/code]
func is_module_enabled(module_name: String) -> bool:
	return ProjectSettings.get_setting("uframe/modules/%s" % module_name, false)
