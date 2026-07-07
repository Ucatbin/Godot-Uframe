@tool
extends EditorPlugin

## UcatFrame 框架插件入口
## 启用插件时自动注册所有 Autoload，禁用时自动移除

#region Autoload 配置
## 需要自动注册的 Autoload 列表
## 格式: [单例名, 脚本路径]
const AUTOLOADS: Array = [
	["UcatFrame", "res://UcatFrameWork/core/UcatFrame.gd"],
	["EventBus", "res://UcatFrameWork/core/EventBus.gd"],
	["Registry", "res://UcatFrameWork/core/Registry.gd"],
	["SaveService", "res://UcatFrameWork/services/SaveService.gd"],
	["AudioService", "res://UcatFrameWork/services/AudioService.gd"],
	["CameraService", "res://UcatFrameWork/services/CameraService.gd"],
	["TransitionService", "res://UcatFrameWork/services/TransitionService.gd"],
]
#endregion

#region 生命周期
func _enter_tree() -> void:
	## 启用插件时自动注册所有 Autoload
	for entry in AUTOLOADS:
		var singleton_name: String = entry[0]
		var script_path: String = entry[1]
		# 检查是否已存在，避免重复添加
		if not has_autoload(singleton_name):
			add_autoload_singleton(singleton_name, script_path)
			print("[UcatFrame] 已注册 Autoload: %s" % singleton_name)

func _exit_tree() -> void:
	## 禁用插件时自动移除所有 Autoload
	for entry in AUTOLOADS:
		var singleton_name: String = entry[0]
		if has_autoload(singleton_name):
			remove_autoload_singleton(singleton_name)
			print("[UcatFrame] 已移除 Autoload: %s" % singleton_name)
#endregion
