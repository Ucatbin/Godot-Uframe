extends Resource

## 加权掉落条目
##
## 作为 [UFrameLootTable] 的 Inspector 配置项，记录内容 ID、相对权重和数量范围。
## 本 Resource 不执行抽取，也不保存运行时保底计数。
## 例如两个有效条目的权重分别为 [code]3[/code] 和 [code]1[/code]，前者被选中的概率是后者的三倍。
class_name UFrameLootEntry

#region Inspector 配置
## 内容 ID，可对应 [UFrameRegistry] 或游戏自有数据源，不限定为物品。
@export var content_id: StringName

## 相对掉落权重；小于等于 [code]0[/code] 时不会被选中。
@export_range(0.0, 1000000.0) var weight := 1.0

## 最小掉落数量。
@export_range(0, 1000000) var min_count := 1

## 最大掉落数量；小于 [member min_count] 时按最小数量处理。
@export_range(0, 1000000) var max_count := 1
#endregion
