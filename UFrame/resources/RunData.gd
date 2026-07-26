extends Resource

'''
用法：
	# 创建自定义存档类
	class_name MyRunData
	extends RunData

	@export var player_level: int = 1
	@export var unlocked_characters: Array[String] = []

	# 然后通过 SaveService 保存/读取
	SaveService.save(MyRunData.new(), "slot_1")
'''
## 默认存档数据 Resource
class_name RunData

#region 基础字段
## [b]存档版本号[/b][br]
## 用于存档迁移/兼容性检查
@export var save_version: int = 1

## [b]游戏总时长（秒）[/b]
@export var play_time: float = 0.0

## [b]存档创建时间戳[/b]
@export var created_at: String = ""

## [b]最后保存时间戳[/b]
@export var last_saved_at: String = ""

## [b]自定义数据字典[/b][br]
## 用于存储不需要强类型的临时数据
@export var custom_data: Dictionary = {}
#endregion

#region 生命周期
func _init() -> void:
	var now = Time.get_datetime_string_from_system()
	created_at = now
	last_saved_at = now
#endregion

#region 工具方法
## [b]设置自定义数据[/b][br][br]
## [param key] : 键[br]
## [param value] : 值
func set_custom(key: String, value: Variant) -> void:
	custom_data[key] = value

## [b]获取自定义数据[/b][br]
## 返回 : 存储的值，不存在时返回 default[br][br]
## [param key] : 键[br]
## [param default] : 默认值
func get_custom(key: String, default: Variant = null) -> Variant:
	return custom_data.get(key, default)

## [b]更新时间戳[/b]
func touch() -> void:
	last_saved_at = Time.get_datetime_string_from_system()
#endregion
