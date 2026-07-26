extends Node

'''
描述：
	存档/读档服务（Autoload 单例）
	负责序列化 Resource 到 user://saves/ 目录

用法：
	# 保存
	SaveService.save(run_data, "slot_1")
	# 读取
	var data = SaveService.load("slot_1")
	# 删除
	SaveService.delete("slot_1")
	# 列出所有存档
	var saves = SaveService.list_saves()
'''

class_name SaveService

#region 常量
const SAVE_DIR := "user://saves/"
#endregion

#region 保存/读取
## [b]保存 Resource 到指定文件[/b][br]
## [br]参数：[br]
## [param data] : 要保存的 Resource[br]
## [param file_name] : 文件名（不含扩展名），默认 "auto_save"[br]
## [br]返回：[/br]
## 是否保存成功
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

## [b]读取存档[/b][br]
## 文件不存在时返回默认实例[br]
## [br]参数：[br]
## [param file_name] : 文件名（不含扩展名），默认 "auto_save"[br]
## [br]返回：[/br]
## 读取到的 Resource，失败时返回默认实例
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

## [b]删除指定存档[/b][br]
## [br]参数：[br]
## [param file_name] : 文件名（不含扩展名）[br]
## [br]返回：[/br]
## 是否删除成功
func delete(file_name: String = "auto_save") -> bool:
	var path := SAVE_DIR + file_name + ".tres"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		print("[SaveService] 已删除: %s" % path)
		return true
	return false

## [b]列出所有存档文件名[/b][br]
## [br]返回：[/br]
## 不含扩展名的文件名数组
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
#endregion

#region 内部方法
## [b]创建默认存档数据[/b][br]
## 优先尝试加载项目的 RunData，否则返回空 Resource
func _create_default_data() -> Resource:
	if ResourceLoader.exists("res://UFrame/resources/RunData.gd"):
		return load("res://UFrame/resources/RunData.gd").new()
	return Resource.new()
#endregion
