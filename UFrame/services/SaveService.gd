extends Node
class_name SaveService

# SaveService.gd
# 存档/读档服务，负责序列化 RunData
# 挂载方式：设为 Autoload，名称 "SaveService"

const SAVE_DIR := "user://saves/"
const AUTO_SAVE_FILE := "user://saves/auto_save.tres"


# ========== 公共方法 ==========

## 保存 RunData 到指定文件
func save(data: Resource, file_name: String = "auto_save") -> bool:
	if data == null:
		push_error("[SaveService] 数据为空，无法保存")
		return false

	# 确保目录存在
	var dir = DirAccess.open("user://")
	if not dir.dir_exists(SAVE_DIR):
		dir.make_dir_recursive(SAVE_DIR)

	var path := SAVE_DIR + file_name + ".tres"
	var err := ResourceSaver.save(data, path)
	if err != OK:
		push_error("[SaveService] 保存失败: %s (错误码: %d)" % [path, err])
		return false

	print("[SaveService] 已保存: %s" % path)
	return true


## 读取 RunData，文件不存在则返回新实例
func load(file_name: String = "auto_save") -> Resource:
	var path := SAVE_DIR + file_name + ".tres"
	if not ResourceLoader.exists(path):
		print("[SaveService] 存档不存在，返回新实例: %s" % path)
		return _create_default_data()

	var data := ResourceLoader.load(path) as Resource
	if data == null:
		push_error("[SaveService] 读取失败: %s" % path)
		return _create_default_data()

	print("[SaveService] 已读取: %s" % path)
	return data


## 删除指定存档
func delete(file_name: String = "auto_save") -> bool:
	var path := SAVE_DIR + file_name + ".tres"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		print("[SaveService] 已删除: %s" % path)
		return true
	return false


## 列出所有存档文件名
func list_saves() -> Array:
	var result: Array = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return result

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			result.append(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()
	return result


# ========== 内部方法 ==========

func _create_default_data() -> Resource:
	# 如果项目有 RunData，实例化它；否则返回空 Resource
	if ResourceLoader.exists("res://UcatFrameWork/resources/RunData.gd"):
		return load("res://UcatFrameWork/resources/RunData.gd").new()
	return Resource.new()
