@tool
extends EditorPlugin

## UFrame 编辑器插件入口
##
## 把整个 [code]addons/uframe[/code] 目录复制到项目后，只需在插件面板中启用一次。
## 本脚本负责补充缺失的项目设置并注册唯一的 [code]UFrame[/code] Autoload，
## 不会覆盖已有设置或其他路径的同名 Autoload。游戏运行时入口见 [code]core/UFrame.gd[/code]。

#region 常量
## Autoload 名称。
const AUTOLOAD_NAME := "UFrame"

## Autoload 脚本路径。
const AUTOLOAD_PATH := "res://addons/uframe/core/UFrame.gd"

## Autoload 在 ProjectSettings 中使用的完整键。
const AUTOLOAD_SETTING := "autoload/UFrame"

## 默认项目设置，只用于补充尚不存在的设置，不会覆盖开发者选择。
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

#region 生命周期
## 插件实例进入编辑器时注册设置的显示信息，并补充新版新增的缺失设置。 [br]
## 编辑器启动和脚本重载都会进入这里，因此不能在此管理持久 Autoload。
func _enter_tree() -> void:
	_ensure_project_settings()

## 用户在“项目设置 → 插件”中启用 UFrame 时完成一次性项目接入。
func _enable_plugin() -> void:
	_ensure_project_settings()
	_ensure_autoload()

## 用户明确禁用 UFrame 时撤销插件注册的运行时入口。 [br]
## 模块设置会保留，重新启用后仍沿用开发者之前的选择。
func _disable_plugin() -> void:
	_remove_autoload()
#endregion

#region 内部方法
## 补充缺失设置，并为 Project Settings 注册布尔类型和基础设置标记。 [br]
## 只有实际新增设置时才写入 [code]project.godot[/code]。
func _ensure_project_settings() -> void:
	var settings_changed := false
	for setting: String in SETTINGS:
		if not ProjectSettings.has_setting(setting):
			ProjectSettings.set_setting(setting, SETTINGS[setting])
			settings_changed = true
		ProjectSettings.add_property_info({
			"name": setting,
			"type": TYPE_BOOL,
		})
		ProjectSettings.set_as_basic(setting, true)
	if not settings_changed:
		return
	var error := ProjectSettings.save()
	if error != OK:
		push_error("[UFramePlugin] 无法保存自动配置：%s" % error_string(error))

## 注册 UFrame Autoload；重复启用时保持幂等。 [br]
## 同名入口属于其他路径时只报告冲突，不修改宿主项目配置。
func _ensure_autoload() -> void:
	var existing_path := _get_autoload_path()
	if existing_path.is_empty():
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
		if not ProjectSettings.has_setting(AUTOLOAD_SETTING):
			push_error("[UFramePlugin] 无法自动注册 UFrame Autoload")
		return
	if existing_path != AUTOLOAD_PATH:
		push_warning("[UFramePlugin] 已存在其他路径的 UFrame Autoload，插件不会覆盖它：%s" % existing_path)

## 仅移除仍然指向插件运行时脚本的 UFrame Autoload。 [br]
## 开发者在启用后改成其他路径时，该入口归宿主项目所有并会被保留。
func _remove_autoload() -> void:
	var existing_path := _get_autoload_path()
	if existing_path == AUTOLOAD_PATH:
		remove_autoload_singleton(AUTOLOAD_NAME)
	elif not existing_path.is_empty():
		push_warning("[UFramePlugin] UFrame Autoload 已指向其他路径，禁用插件时不会删除：%s" % existing_path)

## 返回当前 UFrame Autoload 的规范化资源路径；不存在时返回空字符串。 [br]
## Godot 可能把资源持久化为 [code]uid://[/code]，比较前需要还原成 [code]res://[/code]。
func _get_autoload_path() -> String:
	var setting_value := String(ProjectSettings.get_setting(AUTOLOAD_SETTING, ""))
	var stored_path := setting_value.strip_edges().trim_prefix("*")
	if stored_path.begins_with("uid://"):
		var resource_uid := ResourceUID.text_to_id(stored_path)
		if resource_uid != ResourceUID.INVALID_ID and ResourceUID.has_id(resource_uid):
			return ResourceUID.get_id_path(resource_uid)
	return stored_path
#endregion
