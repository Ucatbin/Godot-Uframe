extends RefCounted

## 全部示例共用的纯 UI 样式工具。
##
## 本脚本只负责创建 StyleBox 和设置控件主题，不保存运行时状态。
## 它不挂载到场景树，由各示例控制器直接调用，也不是 UFrame 的公共 API。

#region 常量
## 示例页面的背景色
const BACKGROUND := Color("#0b1019")
## 普通面板的表面色
const SURFACE := Color("#151d2a")
## 按钮等抬升控件的表面色
const SURFACE_RAISED := Color("#1c2737")
## 控件的默认边框色
const BORDER := Color("#2d3b50")
## 主要文本颜色
const TEXT := Color("#edf4ff")
## 次要文本颜色
const MUTED := Color("#8fa0b8")
## 成功状态颜色
const SUCCESS := Color("#66d9a0")
## 提示状态颜色
const WARNING := Color("#ffca70")
## 危险状态颜色
const DANGER := Color("#ff6b7a")
#endregion

#region 样式方法
## 创建具有统一背景、边框、圆角和内容边距的 StyleBoxFlat
static func panel_style(
	background: Color = SURFACE,
	border: Color = BORDER,
	radius: int = 14,
	content_margin: int = 18
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(content_margin)
	return style

## 为场景中已经存在的面板应用统一样式
static func apply_panel(panel: PanelContainer, accent: Color = Color.TRANSPARENT, margin: int = 18) -> void:
	var border := BORDER if accent.a <= 0.0 else accent.darkened(0.28)
	panel.add_theme_stylebox_override("panel", panel_style(SURFACE, border, 14, margin))

## 为按钮配置普通、悬停、按下和禁用四种状态样式
static func apply_button(button: Button, accent: Color, filled: bool = false) -> void:
	var normal := panel_style(accent.darkened(0.48) if filled else SURFACE_RAISED, accent.darkened(0.30), 9, 10)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = accent.darkened(0.34) if filled else SURFACE_RAISED.lightened(0.08)
	hover.border_color = accent.lightened(0.12)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = accent.darkened(0.56)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = SURFACE.darkened(0.12)
	disabled.border_color = BORDER.darkened(0.25)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", MUTED.darkened(0.25))

## 为场景中已经存在的 Label 设置字号和颜色
## 示例优先在 .tscn 中摆放静态节点，再用本方法补充代码生成的主题资源
static func style_label(label: Label, font_size: int = 16, color: Color = TEXT) -> Label:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

## 为场景中已经存在的 Label 设置标签胶囊样式
static func style_chip(chip: Label, color: Color) -> Label:
	style_label(chip, 12, color.lightened(0.20))
	chip.add_theme_stylebox_override("normal", panel_style(color.darkened(0.66), color.darkened(0.28), 7, 6))
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return chip

## 为场景中已经存在的 ProgressBar 设置统一样式
static func style_progress_bar(bar: ProgressBar, accent: Color) -> ProgressBar:
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", panel_style(Color("#0c121c"), BORDER, 5, 0))
	bar.add_theme_stylebox_override("fill", panel_style(accent.darkened(0.12), accent, 5, 0))
	return bar
#endregion

#region 创建方法
## 创建并设置一个新的 Label
static func make_label(text: String, font_size: int = 16, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	return style_label(label, font_size, color)

## 创建并设置一个新的标签胶囊
static func make_chip(text: String, color: Color) -> Label:
	var chip := Label.new()
	chip.text = text
	return style_chip(chip, color)

## 创建并设置一个新的 ProgressBar
static func make_progress_bar(accent: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	return style_progress_bar(bar, accent)
#endregion
