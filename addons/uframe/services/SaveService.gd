extends Node

## 可选资源存档服务
##
## 通过 [code]UFrame.save[/code] 使用，文件保存在 [code]user://saves/[/code][br]
## 保存按“写临时档 → 旧主档改为备份 → 临时档成为主档”提交[br]
## 读取时自动尝试恢复遗留的临时档或备份档，并忽略 [ResourceLoader] 的旧缓存
class_name UFrameSave

#region 常量
## [b]存档目录[/b]
const SAVE_DIR := "user://saves/"
#endregion

#region 主要方法
## [b]保存资源[/b][br]
## 文件名不含扩展名；成功返回 [code]true[/code][br]
## [UFrameRunData] 会在写入前自动更新时间[br][br]
## [param data] : 需要保存的资源[br]
## [param file_name] : 存档槽名
func save(data: Resource, file_name := "auto_save") -> bool:
	if data == null or not _is_valid_file_name(file_name):
		return false
	if data is UFrameRunData:
		(data as UFrameRunData).touch()
	if not _ensure_save_directory():
		return false
	var paths := _get_paths(file_name)
	var error := ResourceSaver.save(data, paths.temporary)
	if error != OK:
		push_error("[UFrameSave] 写入临时档失败：%s (%d)" % [paths.temporary, error])
		return false
	if FileAccess.file_exists(paths.backup):
		DirAccess.remove_absolute(paths.backup)
	if FileAccess.file_exists(paths.main):
		error = DirAccess.rename_absolute(paths.main, paths.backup)
		if error != OK:
			DirAccess.remove_absolute(paths.temporary)
			return false
	error = DirAccess.rename_absolute(paths.temporary, paths.main)
	if error != OK:
		push_error("[UFrameSave] 提交主档失败：%s (%d)" % [paths.main, error])
		if FileAccess.file_exists(paths.backup):
			DirAccess.rename_absolute(paths.backup, paths.main)
		return false
	if FileAccess.file_exists(paths.backup):
		DirAccess.remove_absolute(paths.backup)
	return true

## [b]读取资源[/b][br]
## 主档损坏或缺失时依次尝试临时档与备份档，并恢复成功候选的正式文件名[br]
## 所有候选都不存在或损坏时返回新的 [UFrameRunData][br][br]
## [param file_name] : 存档槽名
func load(file_name := "auto_save") -> Resource:
	if not _is_valid_file_name(file_name):
		return null
	var paths := _get_paths(file_name)
	var data := _load_resource(paths.main)
	if data:
		_cleanup_recovery_files(paths)
		return data
	data = _load_resource(paths.temporary)
	if data:
		_promote_recovery_file(paths.temporary, paths.main)
		if FileAccess.file_exists(paths.backup):
			DirAccess.remove_absolute(paths.backup)
		return data
	data = _load_resource(paths.backup)
	if data:
		_promote_recovery_file(paths.backup, paths.main)
		return data
	return UFrameRunData.new()

## [b]删除存档槽[/b][br]
## 同时删除主档以及可能遗留的临时档、备份档；至少移除一个文件时返回 [code]true[/code][br][br]
## [param file_name] : 存档槽名
func delete(file_name := "auto_save") -> bool:
	if not _is_valid_file_name(file_name):
		return false
	var removed := false
	var paths := _get_paths(file_name)
	for path: String in [paths.main, paths.temporary, paths.backup]:
		if FileAccess.file_exists(path):
			removed = DirAccess.remove_absolute(path) == OK or removed
	return removed
#endregion

#region 查询方法
## [b]列出正式存档槽[/b][br]
## 返回排序后的槽名数组，不包含 [code].tmp[/code] 与 [code].bak[/code] 恢复文件
func list_saves() -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(SAVE_DIR)
	if directory == null:
		return result
	for file_name in directory.get_files():
		if file_name.ends_with(".tres") \
			and not file_name.ends_with(".tmp.tres") \
			and not file_name.ends_with(".bak.tres"):
			result.append(file_name.get_basename())
	result.sort()
	return result
#endregion

#region 内部方法
## [b]读取候选资源[/b][br]
## 忽略缓存；文件不存在或无法解析时返回 [code]null[/code][br][br]
## [param path] : 候选存档路径
func _load_resource(path: String) -> Resource:
	if not FileAccess.file_exists(path):
		return null
	var data := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	if data == null:
		push_warning("[UFrameSave] 无法读取候选存档：%s" % path)
	return data

## [b]提升恢复文件[/b][br]
## 删除旧目标后把成功读取的候选文件改为正式文件名[br][br]
## [param source] : 恢复文件路径[br]
## [param target] : 正式存档路径
func _promote_recovery_file(source: String, target: String) -> void:
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
	var error := DirAccess.rename_absolute(source, target)
	if error != OK:
		push_warning("[UFrameSave] 已读取恢复档，但无法恢复文件名：%s" % source)

## [b]清理恢复文件[/b][br][br]
## [param paths] : 由 [method _get_paths] 生成的路径表
func _cleanup_recovery_files(paths: Dictionary) -> void:
	for path: String in [paths.temporary, paths.backup]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

## [b]确保存档目录存在[/b]
func _ensure_save_directory() -> bool:
	var root := DirAccess.open("user://")
	if root == null:
		return false
	if root.dir_exists(SAVE_DIR):
		return true
	var error := root.make_dir_recursive(SAVE_DIR)
	if error != OK:
		push_error("[UFrameSave] 无法创建存档目录：%d" % error)
	return error == OK

## [b]生成存档路径表[/b][br]
## 返回主档、临时档和备份档路径[br][br]
## [param file_name] : 存档槽名
func _get_paths(file_name: String) -> Dictionary:
	return {
		"main": SAVE_DIR + file_name + ".tres",
		"temporary": SAVE_DIR + file_name + ".tmp.tres",
		"backup": SAVE_DIR + file_name + ".bak.tres",
	}

## [b]检查存档槽名[/b][br]
## 拒绝空值、非法文件名字符与路径穿越片段[br][br]
## [param file_name] : 需要检查的槽名
func _is_valid_file_name(file_name: String) -> bool:
	return not file_name.is_empty() \
		and file_name == file_name.validate_filename() \
		and not file_name.contains("..")
#endregion
