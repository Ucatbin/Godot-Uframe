extends UFrameResourceData

## 背包示例专用的物品静态数据。
##
## UFrameResourceData 只提供通用字段；具体游戏可以像这里一样扩展自己的
## 分类、颜色和显示方式。每件物品保存为 .tres 后，策划数据便能直接在
## Inspector 中调整，而不需要修改背包逻辑；引用入口可在 loot_demo.tscn 查看。
class_name LootDemoItemData

#region 物品显示配置
## 用于自动整理和详情面板的分类。
@export var category: StringName = &"material"
## 分类排序优先级，数值越小越靠前。
@export_range(0, 100) var category_order := 0
## 代码绘制图标时使用的主色。
@export var display_color := Color.WHITE
## 示例图标类型。正式项目通常直接使用基类提供的 icon 贴图字段。
@export var icon_kind: StringName = &"material"
#endregion
