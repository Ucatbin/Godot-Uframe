class_name UFrameSave
extends Node

## 可选的 Resource 存档服务，通过 UFrame.save 使用，文件保存在 user://saves/。
##
## 保存顺序为“写临时档 → 旧主档改为备份 → 临时档成为主档”。读取时会自动恢复[br]
## 中断后遗留的临时档或备份档，并忽略 ResourceLoader 的旧缓存。

const SAVE_DIR := "user://saves/"

## 保存 Resource 到指定槽位。文件名不含扩展名；成功返回 true。
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

## 读取槽位。主档损坏或缺失时会依次尝试完整的临时档和备份档。
## 所有候选都不存在或损坏时返回一个新的 UFrameRunData。
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

## 删除一个槽位的主档以及可能遗留的临时档、备份档。
func delete(file_name := "auto_save") -> bool:
	if not _is_valid_file_name(file_name):
		return false
	var removed := false
	var paths := _get_paths(file_name)
	for path: String in [paths.main, paths.temporary, paths.backup]:
		if FileAccess.file_exists(path):
			removed = DirAccess.remove_absolute(path) == OK or removed
	return removed

## 列出全部正式存档槽位，不包含 .tmp/.bak 恢复文件。
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

func _load_resource(path: String) -> Resource:
	if not FileAccess.file_exists(path):
		return null
	var data := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	if data == null:
		push_warning("[UFrameSave] 无法读取候选存档：%s" % path)
	return data

func _promote_recovery_file(source: String, target: String) -> void:
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
	var error := DirAccess.rename_absolute(source, target)
	if error != OK:
		push_warning("[UFrameSave] 已读取恢复档，但无法恢复文件名：%s" % source)

func _cleanup_recovery_files(paths: Dictionary) -> void:
	for path: String in [paths.temporary, paths.backup]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

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

func _get_paths(file_name: String) -> Dictionary:
	return {
		"main": SAVE_DIR + file_name + ".tres",
		"temporary": SAVE_DIR + file_name + ".tmp.tres",
		"backup": SAVE_DIR + file_name + ".bak.tres",
	}

func _is_valid_file_name(file_name: String) -> bool:
	return not file_name.is_empty() \
		and file_name == file_name.validate_filename() \
		and not file_name.contains("..")
