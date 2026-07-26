@tool
extends EditorPlugin

'''
描述：
	UcatFrame 框架插件入口
	启用插件时自动注册所有 Autoload 单例，禁用时自动移除

用法：
	1. 将 UFrame/ 文件夹放入项目
	2. 项目设置 → 插件 → 启用 "UcatFrame"
	3. 所有 Autoload 自动注册，无需手动配置
'''

#region Autoload 配置
## [b]需要自动注册的 Autoload 列表[/b][br]
## 格式: [单例名, 脚本路径][br]
## 全部使用 res://UFrame/ 前缀
const AUTOLOADS: Array = [
	["UcatFrame", "res://UFrame/core/UcatFrame.gd"],
	["EventBus", "res://UFrame/core/EventBus.gd"],
	["Registry", "res://UFrame/core/Registry.gd"],
	["SaveService", "res://UFrame/services/SaveService.gd"],
	["AudioService", "res://UFrame/services/AudioService.gd"],
	["CameraService", "res://UFrame/services/CameraService.gd"],
	["TransitionService", "res://UFrame/services/TransitionService.gd"],
	["TweenService", "res://UFrame/services/TweenService.gd"],
]
#endregion

#region 生命周期
func _enter_tree() -> void:
	## [b]启用插件时自动注册所有 Autoload[/b]
	for entry in AUTOLOADS:
		var singleton_name: String = entry[0]
		var script_path: String = entry[1]
		# 检查是否已存在，避免重复添加
		if not has_autoload(singleton_name):
			add_autoload_singleton(singleton_name, script_path)
			print("[UcatFrame] 已注册 Autoload: %s" % singleton_name)

func _exit_tree() -> void:
	## [b]禁用插件时自动移除所有 Autoload[/b]
	for entry in AUTOLOADS:
		var singleton_name: String = entry[0]
		if has_autoload(singleton_name):
			remove_autoload_singleton(singleton_name)
			print("[UcatFrame] 已移除 Autoload: %s" % singleton_name)
#endregion
