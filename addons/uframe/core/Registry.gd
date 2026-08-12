extends Node

## 轻量运行时内容注册表
##
## 将“内容类型 + 唯一 ID”映射到 [Resource]、[PackedScene] 或其他非空值。
## 本脚本只维护调用方显式注册的运行时映射，不扫描场景树，也不负责持久化。
## 运行时通过 [code]UFrame.registry[/code] 使用。
##
## 使用示例：
## [codeblock]
## UFrame.registry.register(&"weapon", &"game:fire_sword", sword_data)
## var sword = UFrame.registry.get_value(&"weapon", &"game:fire_sword")
## UFrame.registry.unregister(&"weapon", &"game:fire_sword")
## [/codeblock]
class_name UFrameRegistry

#region 信号
## 首次注册或覆盖同类型下的已有 ID 后发出。
## [param content_type] 是内容分类，[param content_id] 是该分类下的唯一 ID。
signal content_registered(content_type: StringName, content_id: StringName)

## 仅在 [method unregister] 成功移除一项内容后发出；[method clear] 不会发出该信号。
## [param content_type] 是内容分类，[param content_id] 是已移除的唯一 ID。
signal content_unregistered(content_type: StringName, content_id: StringName)
#endregion

#region 运行时状态
## 内容注册表：内容类型 → {内容 ID → 注册内容}。
var _registry: Dictionary[StringName, Dictionary] = {}
#endregion

#region 主要方法
## 注册非空内容；参数有效时返回 [code]true[/code]。
## 同类型下的重复 ID 会覆盖旧值、发出警告并再次发出 [signal content_registered]。
func register(content_type: StringName, content_id: StringName, value: Variant) -> bool:
	if content_type.is_empty() or content_id.is_empty() or value == null:
		push_error("[UFrameRegistry] content_type、content_id 和 value 不能为空")
		return false
	var bucket: Dictionary = _registry.get_or_add(content_type, {})
	if bucket.has(content_id):
		push_warning("[UFrameRegistry] 重复 ID 已覆盖：%s/%s" % [content_type, content_id])
	bucket[content_id] = value
	content_registered.emit(content_type, content_id)
	return true

## 移除指定内容；目标不存在时返回 [code]false[/code]。
## 类型下没有剩余内容时，会同时清理该类型。
func unregister(content_type: StringName, content_id: StringName) -> bool:
	var bucket: Dictionary = _registry.get(content_type, {})
	if not bucket.erase(content_id):
		return false
	if bucket.is_empty():
		_registry.erase(content_type)
	content_unregistered.emit(content_type, content_id)
	return true

## 非递归扫描目录中的 [code].tres[/code] 与 [code].res[/code] 文件并注册。
## 文件基本名作为 ID；设置 [param prefix] 后格式为 [code]前缀:文件基本名[/code]。
## 返回成功加载并注册的文件数量，覆盖已有 ID 也计入数量。
func register_from_directory(content_type: StringName, directory_path: String, prefix: StringName = &"") -> int:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		push_error("[UFrameRegistry] 无法打开目录：%s" % directory_path)
		return 0
	var registered := 0
	# 目录扫描只在调用方显式请求时发生
	for file_name in directory.get_files():
		if not file_name.ends_with(".tres") and not file_name.ends_with(".res"):
			continue
		var value := ResourceLoader.load(directory_path.path_join(file_name))
		if value == null:
			push_warning("[UFrameRegistry] 资源加载失败：%s" % file_name)
			continue
		var base_name := file_name.get_basename()
		var content_id := StringName(base_name if prefix.is_empty() else "%s:%s" % [prefix, base_name])
		if register(content_type, content_id, value):
			registered += 1
	return registered

## 清理注册内容；[param content_type] 为空时清理整个注册表，否则只清理指定类型。
## 本方法不会发出 [signal content_unregistered]。
func clear(content_type: StringName = &"") -> void:
	if content_type.is_empty():
		_registry.clear()
	else:
		_registry.erase(content_type)
#endregion

#region 查询方法
## 判断指定类型和 ID 的内容是否存在。
func has_value(content_type: StringName, content_id: StringName) -> bool:
	return _registry.has(content_type) and _registry[content_type].has(content_id)

## 获取指定内容；目标不存在时返回 [param default_value]。
func get_value(content_type: StringName, content_id: StringName, default_value: Variant = null) -> Variant:
	return _registry.get(content_type, {}).get(content_id, default_value)

## 获取类型下的全部 ID，返回新的键数组。
func list_ids(content_type: StringName) -> Array:
	return _registry.get(content_type, {}).keys()

## 获取全部内容类型，返回新的键数组。
func list_types() -> Array:
	return _registry.keys()

## 获取类型下的全部内容，返回字典浅拷贝。
func get_all(content_type: StringName) -> Dictionary:
	return _registry.get(content_type, {}).duplicate()
#endregion
