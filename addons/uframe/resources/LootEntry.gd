extends Resource

## 加权掉落条目
##
## 作为 [UFrameLootTable] 的配置项使用，记录内容 ID、相对权重和数量范围[br]
## 例如两个条目的权重分别为 [code]3[/code] 和 [code]1[/code] 时，前者被选中的概率是后者的三倍
class_name UFrameLootEntry

#region 配置
## [b]内容 ID[/b][br]
## 可对应 [UFrameRegistry] 或游戏自有数据源，不限定为物品
@export var content_id: StringName

## [b]相对掉落权重[/b][br]
## 小于等于 [code]0[/code] 时不会被选中
@export_range(0.0, 1000000.0) var weight := 1.0

## [b]最小掉落数量[/b]
@export_range(0, 1000000) var min_count := 1

## [b]最大掉落数量[/b][br]
## 小于 [member min_count] 时按最小数量处理
@export_range(0, 1000000) var max_count := 1
#endregion
