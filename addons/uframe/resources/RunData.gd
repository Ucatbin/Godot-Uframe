class_name UFrameRunData
extends Resource

## 最小存档数据基类。
##
## 推荐为具体游戏创建强类型子类，不要把所有内容都塞进 custom_data：[br]
## [codeblock]
## class_name MySaveData
## extends UFrameRunData
## @export var player_level := 1
## [/codeblock]
## 保存和读取使用 [code]UFrame.save.save(data, "slot_1")[/code]。

## 存档结构版本，用于未来的数据迁移。
@export var save_version := 1
## 累计游戏时间，单位为秒。框架不会自动增加，需要游戏自行维护。
@export var play_time := 0.0
## 首次创建数据时的本地时间字符串。
@export var created_at := ""
## 最近一次保存的本地时间字符串。
@export var last_saved_at := ""
## 少量扩展数据。核心游戏状态应优先使用强类型 @export 字段。
@export var custom_data: Dictionary = {}

func _init() -> void:
	var now := Time.get_datetime_string_from_system()
	created_at = now
	last_saved_at = now

## 写入一项自定义数据。
func set_custom(key: StringName, value: Variant) -> void:
	custom_data[key] = value

## 获取一项自定义数据，不存在时返回 default_value。
func get_custom(key: StringName, default_value: Variant = null) -> Variant:
	return custom_data.get(key, default_value)

## 更新最近保存时间。UFrameSave.save() 会自动调用。
func touch() -> void:
	last_saved_at = Time.get_datetime_string_from_system()
