extends Node

'''
描述：
	UcatFrame 框架总入口（Autoload 单例）
	统一管理框架的初始化流程，提供 framework_ready 信号

用法：
	# 等待框架初始化完成（其他 Autoload 可在 _ready 中监听）
	UcatFrame.framework_ready.connect(_on_framework_ready)

	# 项目可继承此类扩展初始化逻辑
	# 创建 my_game.gd，extends UcatFrame，重写 _init_framework()
'''

#region 变量
## [b]框架版本号[/b]
const VERSION: String = "0.2.0"

## [b]框架名称[/b]
const NAME: String = "UcatFrame"

## [b]初始化完成标记[/b]
var _initialized: bool = false
#endregion

#region 信号
## [b]框架初始化完成[/b][br]
## 在 _ready 末尾发出，此时所有 Autoload 均已就绪
signal framework_ready()
#endregion

#region 生命周期
func _ready() -> void:
	if _initialized:
		return
	_init_framework()
	_initialized = true
	print("[UcatFrame] v%s 初始化完成" % VERSION)
	framework_ready.emit()
#endregion

#region 初始化钩子
## [b]框架初始化[/b][br]
## 子类重写此方法以注册自定义内容[br]
## 初始化顺序：EventBus → Registry → Services[br]
## [br]示例：[br]
## [codeblock]
## func _init_framework():
##     super._init_framework()
##     Registry.register_from_directory("weapon", "res://data/weapons/", "mygame")
## [/codeblock]
func _init_framework() -> void:
	# 框架级初始化逻辑
	# 此时 EventBus、Registry 均已作为 Autoload 就绪
	# 子项目在此注册内容、连接全局事件
	pass
#endregion

#region 工具方法
## [b]获取框架版本[/b][br]
func get_version() -> String:
	return VERSION

## [b]框架是否已初始化[/b]
func is_ready() -> bool:
	return _initialized

## [b][color=cyan]调试[/color][/b]：打印框架状态
func _debug_print() -> void:
	print("[UcatFrame] 版本: %s | 已初始化: %s" % [VERSION, _initialized])
	print("[UcatFrame] EventBus 状态: ", EventBus._debug_get_status())
	Registry._debug_print()
#endregion
