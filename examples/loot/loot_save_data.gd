extends UFrameRunData

## 掉落示例专用存档。
##
## 只保存恢复示例进度所需的背包快照、抽取次数和保底进度；存取流程仍由 UFrameSave
## 负责。本 Resource 不挂载场景树，由 loot_demo.tscn 的控制器按需创建和读取。
class_name LootDemoSaveData

## 64 格背包的顺序快照；空 Dictionary 表示空格。
@export var slots: Array[Dictionary] = []
## 已完成的抽取次数。
@export var roll_count := 0
## 距离下一次保底的连续未命中次数。
@export var pity_misses := 0
