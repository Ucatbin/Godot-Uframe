class_name UFrameResourceData
extends Resource

## 游戏静态数据的可选基类。
##
## 项目可以创建 WeaponData、ItemData 等子类并添加自己的字段：[br]
## [codeblock]
## class_name WeaponData
## extends UFrameResourceData
## @export var damage := 10
## [/codeblock]
## 创建 .tres 后，可通过 [code]UFrame.registry.register(&"weapon", data.id, data)[/code] 注册。

## 全局唯一 ID，推荐使用“项目或模组名:内容名”格式。
@export var id: StringName
## 显示给玩家的名称。正式项目可把它作为本地化键使用。
@export var display_name := ""
## 显示给玩家的说明文字，可以包含 BBCode。
@export_multiline var description := ""
## UI 中显示的图标。
@export var icon: Texture2D
## 用于筛选和分类，例如 fire、ranged。
@export var tags: Array[StringName] = []
## 通用品阶或稀有度。具体含义由游戏项目定义。
@export var tier := 0

## 是否包含指定标签。
func has_tag(tag: StringName) -> bool:
	return tag in tags

## 是否至少包含筛选列表中的一个标签。
func matches_any_tag(filter_tags: Array[StringName]) -> bool:
	for tag in filter_tags:
		if tag in tags:
			return true
	return false

## 获取最终描述。子类可以覆写它来插入动态数值。
func get_description() -> String:
	return description
