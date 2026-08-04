extends Node

## 可选场景管理服务
##
## 通过 [code]UFrame.scenes[/code] 使用，统一管理主场景切换与叠加场景[br]
## [method change_scene] 立即提交普通切换，[method change_scene_async] 在线程中加载大场景[br]
## 只有新场景真正成为 [member SceneTree.current_scene] 后才发出 [signal scene_changed]
class_name UFrameSceneService

#region 常量
## [b]场景确认最大帧数[/b][br]
## Godot 在帧边界完成场景替换，因此同步切换使用有限帧数确认最终结果
const SCENE_CONFIRMATION_MAX_FRAMES := 16
#endregion

#region 信号
## [b]场景即将切换[/b][br]
## 请求通过路径验证、即将提交时发出[br][br]
## [param from] : 当前主场景路径[br]
## [param to] : 目标主场景路径
signal scene_changing(from: String, to: String)

## [b]场景切换完成[/b][br]
## 新场景已经成为 [member SceneTree.current_scene] 时发出[br][br]
## [param new_scene] : 新主场景路径
signal scene_changed(new_scene: String)
#endregion

#region 运行时状态
## [b]当前主场景路径[/b][br]
## 仅在确认切换完成后更新
var current_scene_path := ""

## [b]叠加场景表[/b][br][br]
## [color=cyan]映射：[/color]场景路径 → 当前主场景下的实例。
var _overlay_scenes: Dictionary[String, Node] = {}

## [b]场景请求代次[/b][br]
## 新请求会使仍在等待的旧请求返回 [constant ERR_SKIP]
var _request_generation := 0
#endregion

#region 生命周期
func _ready() -> void:
	var current := get_tree().current_scene
	if current:
		current_scene_path = current.scene_file_path
#endregion

#region 主要方法
## [b]请求普通场景切换[/b][br]
## 返回 Godot [Error]；成功提交后可等待 [signal scene_changed][br][br]
## [param path] : 目标场景路径
func change_scene(path: String) -> Error:
	var request := _submit_scene_change(path)
	var error: Error = request.error
	if error == OK:
		_confirm_scene_change.call_deferred(path, int(request.generation))
	return error

## [b]切换并确认场景[/b][br]
## 等待新场景真正成为 [member SceneTree.current_scene]，适合必须取得最终结果的系统[br][br]
## [param path] : 目标场景路径
func change_scene_confirmed(path: String) -> Error:
	var request := _submit_scene_change(path)
	var error: Error = request.error
	if error != OK:
		return error
	return await _confirm_scene_change(path, int(request.generation))

## [b]异步切换场景[/b][br]
## 在线程中加载场景；返回 [constant OK] 表示新场景已经成为当前主场景[br][br]
## [param path] : 目标场景路径[br]
## [param on_progress] : 可选的加载进度回调，参数范围为 [code]0.0[/code] 到 [code]1.0[/code]
func change_scene_async(path: String, on_progress: Callable = Callable()) -> Error:
	if not _is_valid_scene_path(path):
		return ERR_FILE_NOT_FOUND
	_request_generation += 1
	var generation := _request_generation
	var previous := current_scene_path
	scene_changing.emit(previous, path)
	var error := ResourceLoader.load_threaded_request(path)
	if error != OK:
		push_error("[UFrameSceneService] 无法开始加载：%s (%d)" % [path, error])
		return error
	var progress: Array[float] = []
	while generation == _request_generation:
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				if on_progress.is_valid():
					on_progress.call(progress[0] if not progress.is_empty() else 0.0)
			ResourceLoader.THREAD_LOAD_LOADED:
				var packed := ResourceLoader.load_threaded_get(path) as PackedScene
				if packed == null:
					return ERR_FILE_CORRUPT
				error = get_tree().change_scene_to_packed(packed)
				if error != OK:
					return error
				_clear_overlay_records()
				error = await _confirm_scene_change(path, generation)
				if error != OK:
					return error
				if on_progress.is_valid():
					on_progress.call(1.0)
				return OK
			ResourceLoader.THREAD_LOAD_FAILED:
				return ERR_CANT_OPEN
			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				return ERR_INVALID_DATA
		await get_tree().process_frame
	return ERR_SKIP

## [b]重新加载当前场景[/b]
func reload_current() -> Error:
	var path := current_scene_path
	if path.is_empty() and get_tree().current_scene:
		path = get_tree().current_scene.scene_file_path
	return change_scene(path) if not path.is_empty() else ERR_DOES_NOT_EXIST

## [b]添加叠加场景[/b][br]
## 在当前主场景下实例化；同一路径已有有效实例时直接返回原实例[br][br]
## [param path] : 叠加场景路径
func add_scene(path: String) -> Node:
	if _overlay_scenes.has(path) and is_instance_valid(_overlay_scenes[path]):
		return _overlay_scenes[path]
	if not _is_valid_scene_path(path) or get_tree().current_scene == null:
		return null
	var packed := ResourceLoader.load(path) as PackedScene
	if packed == null:
		return null
	var instance := packed.instantiate()
	get_tree().current_scene.add_child(instance)
	_overlay_scenes[path] = instance
	instance.tree_exited.connect(func() -> void:
		if _overlay_scenes.get(path) == instance:
			_overlay_scenes.erase(path)
	, CONNECT_ONE_SHOT)
	return instance

## [b]移除叠加场景[/b][br]
## 目标存在时排队释放并返回 [code]true[/code][br][br]
## [param path] : 叠加场景路径
func remove_scene(path: String) -> bool:
	var instance := _overlay_scenes.get(path) as Node
	if not is_instance_valid(instance):
		_overlay_scenes.erase(path)
		return false
	_overlay_scenes.erase(path)
	instance.queue_free()
	return true
#endregion

#region 内部方法
## [b]提交普通场景切换[/b][br]
## 返回 [code]error[/code] 与本次请求 [code]generation[/code][br][br]
## [param path] : 目标场景路径
func _submit_scene_change(path: String) -> Dictionary:
	if not _is_valid_scene_path(path):
		return {"error": ERR_FILE_NOT_FOUND, "generation": _request_generation}
	_request_generation += 1
	var generation := _request_generation
	var previous := current_scene_path
	scene_changing.emit(previous, path)
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		push_error("[UFrameSceneService] 场景切换失败：%s (%d)" % [path, error])
		return {"error": error, "generation": generation}
	_clear_overlay_records()
	return {"error": OK, "generation": generation}

## [b]确认场景切换结果[/b][br]
## 在有限帧数内确认目标已经成为当前场景；请求被覆盖时返回 [constant ERR_SKIP][br][br]
## [param path] : 目标场景路径[br]
## [param generation] : 本次请求代次
func _confirm_scene_change(path: String, generation: int) -> Error:
	# 场景切换的提交点位于帧边界。有限轮询既兼容不同渲染后端，
	# 又能在请求被覆盖或引擎没有完成切换时明确返回错误。
	for attempt in range(SCENE_CONFIRMATION_MAX_FRAMES + 1):
		if generation != _request_generation:
			return ERR_SKIP
		if _current_scene_matches(path):
			current_scene_path = path
			scene_changed.emit(path)
			return OK
		if attempt < SCENE_CONFIRMATION_MAX_FRAMES:
			await get_tree().process_frame
	push_error("[UFrameSceneService] 等待新场景超时：%s" % path)
	return ERR_TIMEOUT

## [b]判断当前场景是否匹配[/b][br][br]
## [param path] : 目标场景路径
func _current_scene_matches(path: String) -> bool:
	var current := get_tree().current_scene
	return current != null and current.scene_file_path == path

## [b]检查场景路径[/b][br]
## 空路径或无法作为 [PackedScene] 加载时返回 [code]false[/code][br][br]
## [param path] : 需要检查的场景路径
func _is_valid_scene_path(path: String) -> bool:
	if path.is_empty() or not ResourceLoader.exists(path, "PackedScene"):
		push_error("[UFrameSceneService] 场景不存在：%s" % path)
		return false
	return true

## [b]清理叠加场景记录[/b][br]
## 主场景切换会统一释放叠加节点，本方法只清理持有的引用
func _clear_overlay_records() -> void:
	_overlay_scenes.clear()
#endregion
