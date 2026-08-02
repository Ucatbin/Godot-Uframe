@tool
extends EditorPlugin

## UFrame 编辑器插件入口。
## 启用插件时注册项目设置，并自动创建唯一的 UFrame Autoload。
## 游戏运行时不会执行本脚本；实际入口是 core/UFrame.gd。

## Autoload 名称和路径集中定义，避免安装目录发生变化时到处修改。
const AUTOLOAD_NAME := "UFrame"
const AUTOLOAD_PATH := "res://addons/uframe/core/UFrame.gd"
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

var _owns_autoload := false

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
