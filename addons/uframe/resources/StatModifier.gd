extends Resource

## 单项属性修正资源
##
## 在 Inspector 中配置并交给 [UFrameStats] 使用，按优先级对一个属性执行一种运算。
## 本 Resource 不自行计时；[member duration] 非负时由 [UFrameStats] 记录经过时间并移除。
## 加入 Stats 后应视为不可变；需要修改配置时先移除，修改完成后再重新加入。
class_name UFrameStatModifier

#region 枚举
## 属性运算类型。
enum Op {
	ADD,        ## 加法：[code]stat += value[/code]
	MULTIPLY,   ## 乘法：[code]stat *= value[/code]
	PERCENT,    ## 百分比：[code]stat *= 1 + value[/code]
	OVERRIDE,   ## 覆盖：[code]stat = value[/code]
}
#endregion

#region Inspector 配置
## 目标属性名。
@export var stat_name: String = ""

## 运算类型。
@export var operation: Op = Op.ADD

## 修改值。
@export var value: float = 0.0

## 优先级；数值越小越先计算。
@export var priority: int = 0

## 来源名称，用于调试、显示或批量移除，例如 [code]火焰剑附魔[/code]。
@export var source_name: String = ""

## 持续时间（秒）；负数表示永久，[code]0[/code] 表示立即过期。
@export var duration: float = -1.0
#endregion

#region 主要方法
## 对 [param base_value] 应用当前运算并返回结果。 [br][br]
## [param base_value] : 本次运算的输入值
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

#endregion

#region 查询方法
## 判断本项修正是否已经在 [param elapsed] 秒后过期。 [br][br]
## [param elapsed] : 本项修正已经生效的秒数
func is_expired(elapsed: float) -> bool:
	if duration < 0.0:
		return false
	return elapsed >= duration
#endregion
