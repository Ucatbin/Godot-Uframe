extends Resource

## 单项属性修正资源
##
## 与 [UFrameStats] 配合使用，按优先级对一个属性执行加法、乘法、百分比或覆盖运算[br]
## [member duration] 为负数时永久生效，非负数时由 [UFrameStats] 自动计时并移除
class_name UFrameStatModifier

#region 枚举
## [b]属性运算类型[/b]
enum Op {
	ADD,        ## 加法：[code]stat += value[/code]
	MULTIPLY,   ## 乘法：[code]stat *= value[/code]
	PERCENT,    ## 百分比：[code]stat *= 1 + value[/code]
	OVERRIDE,   ## 覆盖：[code]stat = value[/code]
}
#endregion

#region 配置
## [b]目标属性名[/b]
@export var stat_name: String = ""

## [b]运算类型[/b]
@export var operation: Op = Op.ADD

## [b]修改值[/b]
@export var value: float = 0.0

## [b]优先级[/b][br]
## 数值越小越先计算
@export var priority: int = 0

## [b]来源名称[/b][br]
## 用于调试、显示或批量移除，例如 [code]火焰剑附魔[/code]
@export var source_name: String = ""

## [b]持续时间（秒）[/b][br]
## 负数表示永久，[code]0[/code] 表示立即过期
@export var duration: float = -1.0
#endregion

#region 主要方法
## [b]应用属性修正[/b][br][br]
## [param base_value] : 应用本项修正前的属性值
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

## [b]反向计算属性值[/b][br]
## 覆盖运算无法还原原值，仅返回传入值[br][br]
## [param current_value] : 应用本项修正后的属性值
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
#endregion

#region 查询方法
## [b]判断是否过期[/b][br][br]
## [param elapsed] : 本项修正已经生效的秒数
func is_expired(elapsed: float) -> bool:
	if duration < 0.0:
		return false          # -1 = 永久
	return elapsed >= duration
#endregion
