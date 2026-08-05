extends Node

## 轻量运行时内容注册表
##
## 将“内容类型 + 唯一 ID”映射到 [Resource]、[PackedScene] 或其他非空值[br]
## 通过稳定 ID 查找数据，不负责把运行时内容自动保存到磁盘[br][br]
## [code]示例：[/code]
## [codeblock]
## UFrame.registry.register(&"weapon", &"game:fire_sword", sword_data)
## var sword = UFrame.registry.get_value(&"weapon", &"game:fire_sword")
## UFrame.registry.unregister(&"weapon", &"game:fire_sword")
## [/codeblock]
class_name UFrameRegistry

#region 信号
## 首次注册或覆盖同类型下的已有 ID 后发出[br][br]
## [param content_type] : 内容类型[br]
## [param content_id] : 内容唯一标识符
signal content_registered(content_type: StringName, content_id: StringName)

## 仅在 [method unregister] 成功移除一项内容后发出；[method clear] 不会发出该信号[br][br]
## [param content_type] : 内容类型[br]
## [param content_id] : 内容唯一标识符
signal content_unregistered(content_type: StringName, content_id: StringName)
#endregion

#region 运行时状态
## 内容注册表[br][br]
## [color=cyan]映射：[/color]内容类型 → {内容 ID → 注册内容}。
var _registry: Dictionary[StringName, Dictionary] = {}
#endregion

#region 主要方法
## 注册内容；参数有效时返回 [code]true[/code][br]
## [b]同类型下的重复 ID 会覆盖旧值[/b]、发出[color=yellow]警告[/color]并再次发出 [signal content_registered][br][br]
## [param content_type] : 内容类型[br]
## [param content_id] : 内容唯一标识符[br]
## [param value] : 需要注册的非空内容
func register(content_type: StringName, content_id: StringName, value: Variant) -> bool:
	#检查信息配置是否完整
	if content_type.is_empty() or content_id.is_empty() or value == null:
		push_error("[UFrameRegistry] content_type、content_id 和 value 不能为空")
		return false
	#获取或创建指定分类
	var bucket: Dictionary = _registry.get_or_add(content_type, {})
	#覆盖旧资源
	if bucket.has(content_id):
		push_warning("[UFrameRegistry] 重复 ID 已覆盖：%s/%s" % [content_type, content_id])
	#写入资源
	bucket[content_id] = value
	content_registered.emit(content_type, content_id)
	return true

## 移除内容；成功移除返回 [code]true[/code]，目标不存在返回 [code]false[/code]；类型下没有剩余内容时会同时清理该类型[br][br]
## [param content_type] : 内容类型[br]
## [param content_id] : 内容唯一标识符
func unregister(content_type: StringName, content_id: StringName) -> bool:
	#获取指定分类
	var bucket: Dictionary = _registry.get(content_type, {})
	#尝试移除指定内容并返回结果
	if not bucket.erase(content_id):
		return false
	#自动清理失效类型
	if bucket.is_empty():
		_registry.erase(content_type)
	content_unregistered.emit(content_type, content_id)
	return true

## 从目录注册资源，非递归扫描目录中的 [code].tres[/code] 与 [code].res[/code] 文件[br]
## 文件基本名会成为 ID；设置前缀后格式为 [code]前缀:文件基本名[/code][br]
## 返回成功加载并注册的文件数量，覆盖已有 ID 也计入数量[br][br]
## [param content_type] : 内容类型[br]
## [param directory_path] : 需要扫描的目录路径[br]
## [param prefix] : 可选的 ID 前缀
func register_from_directory(content_type: StringName, directory_path: String, prefix: StringName = &"") -> int:
	#获取指定目录路径
	var directory := DirAccess.open(directory_path)
	if directory == null:
		push_error("[UFrameRegistry] 无法打开目录：%s" % directory_path)
		return 0
	var registered := 0
	#检索符合条件的内容并注册
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

## 清理注册内容[br][br]
## [param content_type] : 内容类型；为空时清理整个注册表，否则只清理指定类型；[br]
## 不会发出 [signal content_unregistered][br]
func clear(content_type: StringName = &"") -> void:
	if content_type.is_empty():
		_registry.clear()
	else:
		_registry.erase(content_type)
#endregion

#region 查询方法
## 判断内容是否存在[br][br]
## [param content_type] : 内容类型[br]
## [param content_id] : 内容唯一标识符
func has_value(content_type: StringName, content_id: StringName) -> bool:
	return _registry.has(content_type) and _registry[content_type].has(content_id)

## 获取内容；目标不存在时返回 [param default_value][br][br]
## [param content_type] : 内容类型[br]
## [param content_id] : 内容唯一标识符[br]
## [param default_value] : 目标不存在时返回的默认值
func get_value(content_type: StringName, content_id: StringName, default_value: Variant = null) -> Variant:
	return _registry.get(content_type, {}).get(content_id, default_value)

## 获取类型下的全部 ID ，返回新的键数组[br][br]
## [param content_type] : 内容类型
func list_ids(content_type: StringName) -> Array:
	return _registry.get(content_type, {}).keys()

## 获取全部内容类型，返回新的键数组
func list_types() -> Array:
	return _registry.keys()

## 获取类型下的全部内容，返回字典浅拷贝[br][br]
## [param content_type] : 内容类型
func get_all(content_type: StringName) -> Dictionary:
	return _registry.get(content_type, {}).duplicate()
#endregion
