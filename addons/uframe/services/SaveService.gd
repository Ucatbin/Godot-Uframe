extends Node

## 可选资源存档服务
##
## 通过 [code]UFrame.save[/code] 使用，负责在 [code]user://saves/[/code] 保存、读取和删除 Resource。
## 保存按“写临时档 → 旧主档改为备份 → 临时档成为主档”提交，读取时会尝试恢复中断文件。
## 本服务不定义具体游戏的存档结构；项目应继承 [UFrameRunData] 创建强类型数据。
class_name UFrameSave

#region 常量
## 所有存档槽及恢复文件所在目录。
const SAVE_DIR := "user://saves/"
#endregion

#region 主要方法
## 保存 Resource；[param file_name] 不含扩展名，成功提交主档时返回 [code]true[/code]。
## [UFrameRunData] 会在写入前自动更新时间。
func save(data: Resource, file_name: String = "auto_save") -> bool:
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

## 读取 Resource；主档损坏或缺失时依次尝试临时档与备份档。
## 成功读取恢复文件后会把它提升为主档；所有候选均不可用时返回新的 [UFrameRunData]。
func load(file_name: String = "auto_save") -> Resource:
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

## 删除存档槽的主档、临时档和备份档；至少移除一个文件时返回 [code]true[/code]。
func delete(file_name: String = "auto_save") -> bool:
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
## 返回排序后的正式存档槽名，不包含 [code].tmp[/code] 与 [code].bak[/code] 恢复文件。
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
## 忽略缓存读取候选 Resource；文件不存在或无法解析时返回 [code]null[/code]。
func _load_resource(path: String) -> Resource:
	if not FileAccess.file_exists(path):
		return null
	var data := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	if data == null:
		push_warning("[UFrameSave] 无法读取候选存档：%s" % path)
	return data

## 删除旧目标后，把成功读取的候选文件改为正式文件名。
func _promote_recovery_file(source: String, target: String) -> void:
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
	var error := DirAccess.rename_absolute(source, target)
	if error != OK:
		push_warning("[UFrameSave] 已读取恢复档，但无法恢复文件名：%s" % source)

## 清理由 [method _get_paths] 生成的临时档和备份档。
func _cleanup_recovery_files(paths: Dictionary) -> void:
	for path: String in [paths.temporary, paths.backup]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

## 确保存档目录存在；创建失败时返回 [code]false[/code]。
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

## 生成包含主档、临时档和备份档的路径表。
func _get_paths(file_name: String) -> Dictionary:
	return {
		"main": SAVE_DIR + file_name + ".tres",
		"temporary": SAVE_DIR + file_name + ".tmp.tres",
		"backup": SAVE_DIR + file_name + ".bak.tres",
	}

## 检查存档槽名，拒绝空值、非法文件名字符与路径穿越片段。
func _is_valid_file_name(file_name: String) -> bool:
	return not file_name.is_empty() \
		and file_name == file_name.validate_filename() \
		and not file_name.contains("..")
#endregion
