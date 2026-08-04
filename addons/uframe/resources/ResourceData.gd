extends Resource

## 游戏静态数据可选基类
##
## 项目可以创建武器、物品等强类型子类并添加字段[br]
## 创建 [code].tres[/code] 后，可按 [member id] 注册到 [UFrameRegistry][br][br]
## [code]示例：[/code]
## [codeblock]
## class_name WeaponData
## extends UFrameResourceData
## @export var damage := 10
##
## UFrame.registry.register(&"weapon", data.id, data)
## [/codeblock]
class_name UFrameResourceData

#region 配置
## [b]全局唯一 ID[/b][br]
## 推荐使用 [code]项目或模组名:内容名[/code] 格式
@export var id: StringName

## [b]显示名称[/b][br]
## 正式项目可将其作为本地化键
@export var display_name := ""

## [b]说明文字[/b][br]
## 可以包含 BBCode
@export_multiline var description := ""

## [b]显示图标[/b]
@export var icon: Texture2D

## [b]内容标签[/b][br]
## 用于筛选和分类，例如 [code]fire[/code]、[code]ranged[/code]
@export var tags: Array[StringName] = []

## [b]内容品阶[/b][br]
## 可表示品阶或稀有度，具体含义由游戏项目定义
@export var tier := 0
#endregion

#region 查询方法
## [b]判断是否包含标签[/b][br][br]
## [param tag] : 需要查找的标签
func has_tag(tag: StringName) -> bool:
	return tag in tags

## [b]判断是否匹配任一标签[/b][br][br]
## [param filter_tags] : 需要匹配的标签列表
func matches_any_tag(filter_tags: Array[StringName]) -> bool:
	for tag in filter_tags:
		if tag in tags:
			return true
	return false

## [b]获取最终说明[/b][br]
## 子类可以覆写本方法以插入动态数值
func get_description() -> String:
	return description
#endregion
