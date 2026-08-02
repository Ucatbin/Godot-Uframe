class_name UFrameRegistry
extends Node

## 数据驱动内容的运行时注册表，通过 [code]UFrame.registry[/code] 使用。
##
## 注册表把“内容类型 + 唯一 ID”映射到 Resource、PackedScene 等对象。[br]
## 例如武器可以使用类型 [code]&"weapon"[/code] 和 ID [code]&"game:fire_sword"[/code]。[br]
## 这样系统只依赖 ID，不必直接引用其他模块的脚本。

signal content_registered(content_type: StringName, content_id: StringName)
signal content_unregistered(content_type: StringName, content_id: StringName)

var _registry: Dictionary[StringName, Dictionary] = {}

## 注册内容。参数为空时返回 false；重复 ID 会覆盖旧值并给出警告。
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

## 移除一项内容。成功移除返回 true，目标不存在返回 false。
func unregister(content_type: StringName, content_id: StringName) -> bool:
	var bucket: Dictionary = _registry.get(content_type, {})
	if not bucket.erase(content_id):
		return false
	if bucket.is_empty():
		_registry.erase(content_type)
	content_unregistered.emit(content_type, content_id)
	return true

## 扫描目录中的 .tres/.res 并注册，返回成功注册的数量。
## 文件名会成为 ID；设置 prefix 后格式为 [code]prefix:文件名[/code]。
func register_from_directory(content_type: StringName, directory_path: String, prefix: StringName = &"") -> int:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		push_error("[UFrameRegistry] 无法打开目录：%s" % directory_path)
		return 0
	var registered := 0
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

## 判断某个类型下是否存在指定 ID。
func has_value(content_type: StringName, content_id: StringName) -> bool:
	return _registry.has(content_type) and _registry[content_type].has(content_id)

## 获取内容。目标不存在时返回 [param default_value]。
func get_value(content_type: StringName, content_id: StringName, default_value: Variant = null) -> Variant:
	return _registry.get(content_type, {}).get(content_id, default_value)

## 返回指定类型的全部 ID。返回数组可安全修改，不会影响注册表。
func list_ids(content_type: StringName) -> Array:
	return _registry.get(content_type, {}).keys()

## 返回当前存在的全部内容类型。
func list_types() -> Array:
	return _registry.keys()

## 返回指定类型的字典副本。
func get_all(content_type: StringName) -> Dictionary:
	return _registry.get(content_type, {}).duplicate()

## 清空一个类型；content_type 为空时清空整个注册表。
func clear(content_type: StringName = &"") -> void:
	if content_type.is_empty():
		_registry.clear()
	else:
		_registry.erase(content_type)
