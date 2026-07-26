extends Resource

'''
用法：
	1. 在编辑器中：新建 Resource，类型选 "WeaponData(继承 DataComponent)"
	2. 填写 id/display_name/description/icon
	3. 在游戏初始化时：
		Registry.register("weapon", resource.id, resource)
扩展：
	各游戏项目创建自己的子类，如 WeaponData extends DataComponent，
	再加 damage/attack_speed 等字段。
'''
## 所有框架数据 Resource 的基类
class_name DataComponent

#region 变量
## [b]唯一标识符[/b][br]
## 建议格式 [code]"mod:name"[/code]
@export var id: String = ""

## [b]显示名称[/b]
@export var display_name: String = ""

## [b]描述文本[/b][br]
## 支持 BBCode
@export_multiline var description: String = ""

## [b]图标[/b][br]
@export var icon: Texture2D = null

## [b]内部标签[/b][br]
## 用于过滤/分类，如 ["weapon","ranged","fire"]
@export var tags: Array[String] = []

## [b]品阶/稀有度[/b][br]
@export var tier: int = 0
#endregion

#region 工具方法
## [b]检查是否有特定标签[/b][br][br]
## [param tag] : 标签
func has_tag(tag: String) -> bool:
	return tag in tags

## [b]检查是否有特定标签组[/b][br][br]
## [param filter_tags] : 标签组
func matches_any_tag(filter_tags: Array[String]) -> bool:
	for t in filter_tags:
		if t in tags:
			return true
	return false

## [b]获取描述[/b][br]
## 支持动态数值
func get_description() -> String:
	return description
#endregion
