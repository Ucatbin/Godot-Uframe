extends Resource

## 最小存档数据基类
##
## 推荐为具体游戏创建强类型子类，不要把核心状态全部放入 [member custom_data][br]
## 通过 [method UFrameSave.save] 和 [method UFrameSave.load] 保存或读取[br][br]
## [code]示例：[/code]
## [codeblock]
## class_name MySaveData
## extends UFrameRunData
## @export var player_level := 1
##
## UFrame.save.save(data, "slot_1")
## [/codeblock]
class_name UFrameRunData

#region 配置
## [b]存档结构版本[/b][br]
## 可用于后续数据迁移
@export var save_version := 1

## [b]累计游戏时间[/b][br]
## 单位为秒，框架不会自动增加
@export var play_time := 0.0

## [b]创建时间[/b][br]
## 首次创建数据时的本地时间字符串
@export var created_at := ""

## [b]最近保存时间[/b][br]
## [method UFrameSave.save] 会自动更新
@export var last_saved_at := ""

## [b]扩展数据[/b][br]
## 适合少量可选数据；核心游戏状态应优先使用强类型 [code]@export[/code] 字段
@export var custom_data: Dictionary = {}
#endregion

#region 生命周期
func _init() -> void:
	var now := Time.get_datetime_string_from_system()
	created_at = now
	last_saved_at = now
#endregion

#region 主要方法
## [b]写入扩展数据[/b][br][br]
## [param key] : 数据键[br]
## [param value] : 数据值
func set_custom(key: StringName, value: Variant) -> void:
	custom_data[key] = value

## [b]更新保存时间[/b][br]
## [method UFrameSave.save] 会自动调用
func touch() -> void:
	last_saved_at = Time.get_datetime_string_from_system()
#endregion

#region 查询方法
## [b]获取扩展数据[/b][br]
## 目标不存在时返回 [param default_value][br][br]
## [param key] : 数据键[br]
## [param default_value] : 目标不存在时返回的默认值
func get_custom(key: StringName, default_value: Variant = null) -> Variant:
	return custom_data.get(key, default_value)
#endregion
