extends Node

'''
描述：
	内容注册总线（Autoload 单例）
	所有内容必须通过注册表注册，获得唯一 ID
	跨模块通过 ID 引用，不直接依赖彼此的代码
职责：
	注册游戏内所有可被定义内容
	{"weapon", "item", "character", "skill", "buff", "loot_table", "wave", "recipe"}
用法：
	# 注册一个武器
	Registry.register("weapon", "mygame:fire_sword", preload("res://weapons/fire_sword.tres"))
	# 获取武器
	var sword = Registry.get_value("weapon", "mygame:fire_sword")
	# 遍历所有武器
	for id in Registry.list_ids("weapon"):
		print(id, Registry.get_value("weapon", id))
'''

#region 信号
## [b]注册表注册完成时触发[/b][br][br]
## [param content_type] : 注册到的类型[br]
## [param content_id] : 唯一标识符
signal content_registered(content_type: String, content_id: String)

## [b]注册表注销完成时触发[/b][br][br]
## [param content_type] : 注册到的类型[br]
## [param content_id] : 唯一标识符
signal content_unregistered(content_type: String, content_id: String)
#endregion

#region 变量
## [b]注册表[/b][br][br]
## 映射 ： [param content_type] -> { [param content_id] -> [param resource_or_script] }
var _registry: Dictionary = {}
#endregion

#region 公共方法
## [b]注册内容到指定类型下[/b][br][br]
## [param content_type] : 内容类型，如 "weapon"、"enemy"、"item"、"skill"[br]
## [param content_id] : 唯一标识符，建议格式 [code]"modname:content_name"[/code][br]
## [param value] : 内容本体（通常是 [Resource]，也可以是脚本/场景）
func register(content_type: String, content_id: String, value: Variant) -> void:
	if not _registry.has(content_type):
		_registry[content_type] = {}

	var bucket: Dictionary = _registry[content_type]

	if bucket.has(content_id):
		push_warning("[Registry] 重复注册，已覆盖: %s / %s" % [content_type, content_id])

	bucket[content_id] = value
	content_registered.emit(content_type, content_id)

## [b]从注册表移除内容[/b][br][br]
## [param content_type] : 内容类型[br]
## [param content_id] : 唯一标识符
func unregister(content_type: String, content_id: String) -> void:
	if not _registry.has(content_type):
		return
	if not _registry[content_type].has(content_id):
		return

	_registry[content_type].erase(content_id)
	content_unregistered.emit(content_type, content_id)
	
## [b]自动注册[/b][br]
## 扫描目录，自动注册所有 .tres / .res 文件，生成的 ID 格式为：[code]"prefix:filename"[/code][br][br]
## [param content_type] : 注册到的类型[br]
## [param dir_path] : 如 "res://data/weapons/"[br]
## [param id_prefix] : 可选，如 "mygame"
func register_from_directory(content_type: String, dir_path: String, id_prefix: String = "") -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		push_error("[Registry] 目录不存在: %s" % dir_path)
		return

	var dir = DirAccess.open(dir_path)
	if dir == null:
		push_error("[Registry] 无法打开目录: %s" % dir_path)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			if file_name.ends_with(".tres") or file_name.endswith(".res"):
				var base_name = file_name.get_basename()
				var full_path = dir_path + file_name
				var res = load(full_path)

				var content_id: String
				if id_prefix.is_empty():
					content_id = base_name
				else:
					content_id = "%s:%s" % [id_prefix, base_name]

				register(content_type, content_id, res)

		file_name = dir.get_next()
	dir.list_dir_end()

## [b]检查某个内容是否已注册[/b][br][br]
## [param content_type] : 内容类型[br]
## [param content_id] : 唯一标识符
func has_value(content_type: String, content_id: String) -> bool:
	if not _registry.has(content_type):
		return false
	return _registry[content_type].has(content_id)

## [b]获取已注册的内容，如果获取失败返回 [param default][/b][br][br]
## [param content_type] : 内容类型[br]
## [param content_id] : 唯一标识符[br]
## [param default] : 默认返回值
func get_value(content_type: String, content_id: String, default: Variant = null) -> Variant:
	if not has_value(content_type, content_id):
		return default
	return _registry[content_type][content_id]

## [b]列出某个类型下所有已注册的ID[/b][br][br]
## [param content_type] : 内容类型
func list_ids(content_type: String) -> Array:
	if not _registry.has(content_type):
		return []
	return _registry[content_type].keys()

## [b]列出所有已注册的内容类型[/b][br]
## 返回
func list_types() -> Array:
	return _registry.keys()

## [b]返回某类型下所有内容的字典副本[/b][br][br]
## [param content_type] : 类型名称
func get_all(content_type: String) -> Dictionary:
	if not _registry.has(content_type):
		return {}
	return _registry[content_type].duplicate()
#endregion

#region 内部方法
## [color=cyan]返回 : [/color]查看已注册内容
func _debug_print() -> void:
	print("[Registry] 当前注册内容：")
	for ctype in _registry:
		print("  类型: %s (%d 项)" % [ctype, _registry[ctype].size()])
		for cid in _registry[ctype]:
			print("    - %s" % cid)
#endregion
