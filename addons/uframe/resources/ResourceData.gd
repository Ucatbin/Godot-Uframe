extends Resource

## 游戏静态数据可选基类
##
## 项目可以创建武器、物品等强类型子类，在 Inspector 中生成和配置 [code].tres[/code]。
## 本 Resource 只提供通用显示与分类字段，不定义具体玩法规则；可按 [member id] 注册到 [UFrameRegistry]。
##
## 使用示例：
## [codeblock]
## class_name WeaponData
## extends UFrameResourceData
## @export var damage := 10
##
## UFrame.registry.register(&"weapon", data.id, data)
## [/codeblock]
class_name UFrameResourceData

#region Inspector 配置
## 全局唯一 ID，推荐使用 [code]项目或模组名:内容名[/code] 格式。
@export var id: StringName

## 显示名称；正式项目可将其作为本地化键。
@export var display_name: String = ""

## 说明文字，可以包含 BBCode。
@export_multiline var description: String = ""

## 显示图标。
@export var icon: Texture2D

## 用于筛选和分类的内容标签，例如 [code]fire[/code]、[code]ranged[/code]。
@export var tags: Array[StringName] = []

## 内容品阶，可表示品阶或稀有度，具体含义由游戏项目定义。
@export var tier: int = 0
#endregion

#region 查询方法
## 判断是否包含指定标签。 [br][br]
## [param tag] : 待查询的标签
func has_tag(tag: StringName) -> bool:
	return tag in tags

## 判断是否匹配 [param filter_tags] 中的任一标签。 [br][br]
## [param filter_tags] : 待匹配的标签数组
func matches_any_tag(filter_tags: Array[StringName]) -> bool:
	for tag in filter_tags:
		if tag in tags:
			return true
	return false

## 获取最终说明；子类可以覆写本方法以插入动态数值。
func get_description() -> String:
	return description
#endregion
