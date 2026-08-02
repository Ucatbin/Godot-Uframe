class_name UFrameStatModifier
extends Resource

## 对单个属性施加运算的 Resource，与 UFrameStats 配合使用。
## Duration 为负数表示永久；非负数会由 UFrameStats 自动计时并移除。

#region 枚举
## [b]运算类型[/b]
enum Op {
	ADD,        ## 加法：stat += value
	MULTIPLY,   ## 乘法：stat *= value
	PERCENT,    ## 百分比加成：stat *= (1 + value)  —— value=0.5 表示 +50%
	OVERRIDE,   ## 覆盖：stat = value
}
#endregion

#region 变量
## [b]要修改的属性名[/b]
@export var stat_name: String = ""

## [b]运算类型[/b]
@export var operation: Op = Op.ADD

## [b]修改值[/b]
@export var value: float = 0.0

## [b]优先级[/b][br]
## 数值越小越先计算，默认 0
@export var priority: int = 0

## [b]来源名称[/b][br]
## 用于调试/显示，如 "火焰剑附魔"
@export var source_name: String = ""

## [b]持续时间（秒）[/b][br]
## -1 表示永久，0 表示立即过期
@export var duration: float = -1.0
#endregion

#region 公开方法
## [b]对传入值应用修正[/b]
func apply(base_value: float) -> float:
	match operation:
		Op.ADD:
			return base_value + value
		Op.MULTIPLY:
			return base_value * value
		Op.PERCENT:
			return base_value * (1.0 + value)
		Op.OVERRIDE:
			return value
	return base_value

## [b]反向计算（用于移除 Modifier 时）[/b]
func revert(current_value: float) -> float:
	match operation:
		Op.ADD:
			return current_value - value
		Op.MULTIPLY:
			return current_value / maxf(value, 0.0001)
		Op.PERCENT:
			return current_value / (1.0 + value)
		Op.OVERRIDE:
			return current_value  # 无法还原
	return current_value

## [b]是否过期[/b]
func is_expired(elapsed: float) -> bool:
	if duration < 0.0:
		return false          # -1 = 永久
	return elapsed >= duration
#endregion
