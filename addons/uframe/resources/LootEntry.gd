class_name UFrameLootEntry
extends Resource

## UFrameLootTable 中的一条掉落配置。
##
## 在 UFrameLootTable 的 Entries 数组中创建 UFrameLootEntry，然后填写内容 ID、权重和数量范围。[br]
## 权重是相对值：两个条目的权重分别为 3 和 1 时，前者被选中的概率是后者的三倍。

## 对应 UFrame.registry 或其他数据源中的内容 ID。它不要求内容一定是“物品”。
@export var content_id: StringName
## 相对掉落权重。小于等于 0 的条目不会被选中。
@export_range(0.0, 1000000.0) var weight := 1.0
## 一次掉落的最小数量。
@export_range(0, 1000000) var min_count := 1
## 一次掉落的最大数量。小于 min_count 时会自动按 min_count 处理。
@export_range(0, 1000000) var max_count := 1
