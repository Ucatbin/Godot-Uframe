@tool
extends EditorPlugin

## UFrame 编辑器插件入口
##
## 启用插件时补充缺失的项目设置，并注册唯一的 [code]UFrame[/code] Autoload[br]
## 不会覆盖宿主项目已有的设置或同名 Autoload；游戏运行时入口为 [code]core/UFrame.gd[/code]

#region 常量
## [b]Autoload 名称[/b]
const AUTOLOAD_NAME := "UFrame"

## [b]Autoload 脚本路径[/b]
const AUTOLOAD_PATH := "res://addons/uframe/core/UFrame.gd"

## [b]默认项目设置[/b][br]
## 只用于补充尚不存在的设置，不会覆盖开发者选择
const SETTINGS := {
	"uframe/modules/registry": true,
	"uframe/modules/save": true,
	"uframe/modules/audio": true,
	"uframe/modules/scene": true,
	"uframe/modules/transition": true,
	"uframe/modules/input": false,
	"uframe/modules/camera": false,
	"uframe/debug/logging": true,
}
#endregion

#region 运行时状态
## [b]Autoload 所有权[/b][br]
## 仅当同名入口指向本插件脚本时为 [code]true[/code]
var _owns_autoload := false
#endregion

#region 生命周期
func _enter_tree() -> void:
	# 只写入不存在的设置，绝不覆盖开发者已经选择的模块开关。
	for setting: String in SETTINGS:
		if not ProjectSettings.has_setting(setting):
			ProjectSettings.set_setting(setting, SETTINGS[setting])
		ProjectSettings.set_as_basic(setting, true)
	ProjectSettings.save()
	var autoload_setting := "autoload/%s" % AUTOLOAD_NAME
	if not ProjectSettings.has_setting(autoload_setting):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
		_owns_autoload = true
	else:
		var existing_path := String(ProjectSettings.get_setting(autoload_setting)).trim_prefix("*")
		_owns_autoload = existing_path == AUTOLOAD_PATH
		if not _owns_autoload:
			push_warning("[UFrame] 已存在其他路径的 UFrame Autoload，插件不会覆盖它：%s" % existing_path)

func _exit_tree() -> void:
	# 只移除仍指向本插件路径的入口，绝不删除宿主项目的同名 Autoload。
	var autoload_setting := "autoload/%s" % AUTOLOAD_NAME
	var existing_path := String(ProjectSettings.get_setting(autoload_setting, "")).trim_prefix("*")
	if _owns_autoload and existing_path == AUTOLOAD_PATH:
		remove_autoload_singleton(AUTOLOAD_NAME)
#endregion
