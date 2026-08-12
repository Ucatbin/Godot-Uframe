extends Resource

## 最小存档数据基类
##
## 通过 [method UFrameSave.save] 和 [method UFrameSave.load] 保存或读取。
## 本 Resource 不自动累计游戏时间，也不定义具体游戏状态；项目应创建强类型子类，
## 不要把核心状态全部放入 [member custom_data]。
##
## 使用示例：
## [codeblock]
## class_name MySaveData
## extends UFrameRunData
## @export var player_level := 1
##
## UFrame.save.save(data, "slot_1")
## [/codeblock]
class_name UFrameRunData

#region Inspector 配置
## 存档结构版本，可用于后续数据迁移。
@export var save_version: int = 1

## 累计游戏时间，单位为秒；框架不会自动增加。
@export var play_time: float = 0.0

## 首次创建数据时的本地时间字符串。
@export var created_at: String = ""

## 最近保存时间；[method UFrameSave.save] 会自动更新。
@export var last_saved_at: String = ""

## 少量可选扩展数据；核心游戏状态应优先使用强类型 [code]@export[/code] 字段。
@export var custom_data: Dictionary = {}
#endregion

#region 生命周期
func _init() -> void:
	var now := Time.get_datetime_string_from_system()
	created_at = now
	last_saved_at = now
#endregion

#region 主要方法
## 写入一项扩展数据；同名键会覆盖旧值。
func set_custom(key: StringName, value: Variant) -> void:
	custom_data[key] = value

## 更新最近保存时间；[method UFrameSave.save] 会自动调用。
func touch() -> void:
	last_saved_at = Time.get_datetime_string_from_system()
#endregion

#region 查询方法
## 获取扩展数据；目标不存在时返回 [param default_value]。
func get_custom(key: StringName, default_value: Variant = null) -> Variant:
	return custom_data.get(key, default_value)
#endregion
