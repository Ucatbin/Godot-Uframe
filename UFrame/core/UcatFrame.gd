extends Node

'''
描述：
	UcatFrame 框架总入口（Autoload 单例）
	统一管理框架的初始化流程，提供扩展钩子

用法：
	# 项目可继承此类扩展初始化逻辑（不推荐直接修改本文件）
	# 创建 my_game.gd，extends UcatFrame，重写 _init_framework()
	# 然后在插件中将 Autoload 换为 my_game.gd

	# 在 Autoload 中设为 "UcatFrame"
'''

#region 变量
## [b]框架版本号[/b]
const VERSION: String = "0.2.0"

## [b]框架名称[/b]
const NAME: String = "UcatFrame"

## [b]初始化完成标记[/b]
var _initialized: bool = false
#endregion

#region 生命周期
func _ready() -> void:
	if _initialized:
		return
	_init_framework()
	_initialized = true
	print("[UcatFrame] v%s 初始化完成" % VERSION)
#endregion

#region 初始化钩子
## [b]框架初始化[/b][br]
## 子类重写此方法以注册自定义内容[br]
## [br]示例：[br]
## [codeblock]
## func _init_framework():
##     super._init_framework()
##     Registry.register_from_directory("weapon", "res://data/weapons/", "mygame")
## [/codeblock]
func _init_framework() -> void:
	# 框架级初始化逻辑（如有需要在此添加）
	pass
#endregion

#region 工具方法
## [b]获取框架版本[/b][br]
## [br]返回：[/br]
## 版本字符串，如 "0.2.0"
func get_version() -> String:
	return VERSION

## [b][color=cyan]调试[/color][/b]：[br]
## 打印框架状态
func _debug_print() -> void:
	print("[UcatFrame] 版本: %s | 已初始化: %s" % [VERSION, _initialized])
	print("[UcatFrame] EventBus 状态: ", EventBus._debug_get_status())
	Registry._debug_print()
#endregion
