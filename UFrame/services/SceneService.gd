extends Node

'''
描述：
	场景管理服务（Autoload 单例）
	统一管理场景加载、切换、堆栈

用法：
	# 直接切换
	SceneService.change_scene("res://levels/level2.tscn")

	# 带过渡效果
	await TransitionService.fade_out()
	SceneService.change_scene("res://levels/level2.tscn")

	# 异步加载（带进度）
	SceneService.change_scene_async("res://levels/level2.tscn", func(p): progress_bar.value = p)

	# 附加场景（不替换当前场景）
	SceneService.add_scene("res://ui/dialog.tscn")
'''

class_name SceneService

#region 变量
## [b]当前主场景路径[/b]
var current_scene_path: String = ""

## [b]已加载的附加场景[/b][br]
## { path: Node }
var _overlay_scenes: Dictionary = {}
#endregion

#region 信号
## [b]场景即将切换[/b]
signal scene_changing(from: String, to: String)

## [b]场景切换完成[/b]
signal scene_changed(new_scene: String)
#endregion

#region 场景切换
## [b]同步切换场景[/b]
func change_scene(path: String) -> void:
	var previous = current_scene_path
	scene_changing.emit(previous, path)
	
	# 清理附加场景
	for overlay_path in _overlay_scenes:
		var overlay = _overlay_scenes[overlay_path]
		if is_instance_valid(overlay):
			overlay.queue_free()
	_overlay_scenes.clear()
	
	get_tree().change_scene_to_file(path)
	current_scene_path = path
	scene_changed.emit(path)

## [b]异步加载场景（带进度回调）[/b]
func change_scene_async(path: String, on_progress: Callable = Callable()) -> void:
	var previous = current_scene_path
	scene_changing.emit(previous, path)

	# 清理附加场景
	for overlay_path in _overlay_scenes:
		var overlay = _overlay_scenes[overlay_path]
		if is_instance_valid(overlay):
			overlay.queue_free()
	_overlay_scenes.clear()

	var err = ResourceLoader.load_threaded_request(path)
	if err != OK:
		push_error("[SceneService] 无法加载场景: %s" % path)
		return

	var progress_arr: Array[float] = []
	while true:
		var status := ResourceLoader.load_threaded_get_status(path, progress_arr)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				if on_progress.is_valid():
					on_progress.call(progress_arr[0])
			ResourceLoader.THREAD_LOAD_LOADED:
				if on_progress.is_valid():
					on_progress.call(1.0)
				var scene := ResourceLoader.load_threaded_get(path) as PackedScene
				if scene:
					get_tree().change_scene_to_packed(scene)
				current_scene_path = path
				scene_changed.emit(path)
				break
			ResourceLoader.THREAD_LOAD_FAILED:
				push_error("[SceneService] 场景加载失败: %s" % path)
				break
		await get_tree().process_frame

## [b]重新加载当前场景[/b]
func reload_current() -> void:
	if not current_scene_path.is_empty():
		change_scene(current_scene_path)
	else:
		get_tree().reload_current_scene()
#endregion

#region 附加场景（Overlay / UI）
## [b]在当前场景上叠加一个场景（如 UI 弹窗）[/b]
func add_scene(path: String) -> Node:
	if _overlay_scenes.has(path):
		return _overlay_scenes[path]

	var scene := load(path) as PackedScene
	if scene == null:
		push_error("[SceneService] 无法加载附加场景: %s" % path)
		return null

	var instance := scene.instantiate()
	get_tree().current_scene.add_child(instance)
	_overlay_scenes[path] = instance
	return instance

## [b]移除附加场景[/b]
func remove_scene(path: String) -> void:
	if not _overlay_scenes.has(path):
		return
	var node = _overlay_scenes[path]
	if is_instance_valid(node):
		node.queue_free()
	_overlay_scenes.erase(path)
#endregion
