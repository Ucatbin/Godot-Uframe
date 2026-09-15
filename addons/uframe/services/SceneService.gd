extends Node

## 可选场景管理服务
##
## 通过 [code]UFrame.scenes[/code] 使用，统一管理主场景切换与叠加场景。
## [method change_scene] 立即提交普通切换，[method change_scene_async] 在线程中加载大场景。
## 本服务不负责画面遮罩；需要淡变效果时由 [UFrameTransition] 编排。
## 只有新场景真正成为 [member SceneTree.current_scene] 后才发出 [signal scene_changed]。
class_name UFrameSceneService

#region 信号
## 请求通过路径验证、即将提交时发出。 [br][br]
## [param from] : 当前主场景路径 [br]
## [param to] : 目标主场景路径
signal scene_changing(from: String, to: String)

## 新场景已经成为 [member SceneTree.current_scene] 时发出。 [br][br]
## [param new_scene] : 已确认生效的新主场景路径
signal scene_changed(new_scene: String)
#endregion

#region 运行时状态
## 直接读取 SceneTree 的当前主场景路径；切换间隙或不在树中时为空。
## 原生场景切换也会立即反映在此查询中，不维护第二份场景状态。
var current_scene_path: String:
	get:
		var tree := get_tree() if is_inside_tree() else null
		return tree.current_scene.scene_file_path if tree and tree.current_scene else ""

## 叠加场景表：场景路径 → 当前主场景下的实例。
var _overlay_scenes: Dictionary[String, Node] = {}

## 场景请求代次；新请求会使仍在等待的旧请求返回 [constant ERR_SKIP]。
var _request_generation := 0
#endregion

#region 主要方法
## 提交普通场景切换并返回 Godot [code]Error[/code]；成功提交后可等待 [signal scene_changed]。 [br][br]
## [param path] : 目标资源路径
func change_scene(path: String) -> Error:
	var request := _submit_scene_change(path)
	var error: Error = request.error
	if error == OK:
		_confirm_scene_change.call_deferred(path, int(request.generation))
	return error

## 切换并等待目标真正成为 [member SceneTree.current_scene]，返回最终 Godot [code]Error[/code]。 [br][br]
## [param path] : 目标资源路径
func change_scene_confirmed(path: String) -> Error:
	var request := _submit_scene_change(path)
	var error: Error = request.error
	if error != OK:
		return error
	return await _confirm_scene_change(path, int(request.generation))

## 在线程中加载并切换场景；返回 [constant OK] 表示新场景已经成为当前主场景。 [br][br]
## [param path] : 目标资源路径 [br]
## [param on_progress] : 可选加载进度回调，接收 [code]0.0[/code] 到 [code]1.0[/code] 的进度值
func change_scene_async(path: String, on_progress: Callable = Callable()) -> Error:
	if not _is_valid_scene_path(path):
		return ERR_FILE_NOT_FOUND
	_request_generation += 1
	var generation := _request_generation
	var previous := current_scene_path
	scene_changing.emit(previous, path)
	if generation != _request_generation:
		return ERR_SKIP
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

## 重新加载当前主场景；没有可用路径时返回 [constant ERR_DOES_NOT_EXIST]。
func reload_current() -> Error:
	var path := current_scene_path
	return change_scene(path) if not path.is_empty() else ERR_DOES_NOT_EXIST

## 在当前主场景下添加叠加场景；同一路径已有有效实例时直接返回原实例。 [br]
## 路径无效、加载失败或没有当前主场景时返回 [code]null[/code]。 [br][br]
## [param path] : 目标资源路径
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

## 移除叠加场景；目标存在时排队释放并返回 [code]true[/code]。 [br][br]
## [param path] : 目标资源路径
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
## 提交普通场景切换，返回 [code]error[/code] 与本次请求的 [code]generation[/code]。 [br][br]
## [param path] : 目标资源路径
func _submit_scene_change(path: String) -> Dictionary:
	if not _is_valid_scene_path(path):
		return {"error": ERR_FILE_NOT_FOUND, "generation": _request_generation}
	_request_generation += 1
	var generation := _request_generation
	var previous := current_scene_path
	scene_changing.emit(previous, path)
	if generation != _request_generation:
		return {"error": ERR_SKIP, "generation": generation}
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		push_error("[UFrameSceneService] 场景切换失败：%s (%d)" % [path, error])
		return {"error": error, "generation": generation}
	_clear_overlay_records()
	return {"error": OK, "generation": generation}

## 等待原生 SceneTree.scene_changed 后确认目标；请求被覆盖时返回 ERR_SKIP。 [br]
## 成功提交才进入此方法，失败在提交阶段直接返回；无需按固定帧数轮询。 [br][br]
## [param path] : 目标资源路径 [br]
## [param generation] : 本次请求的代次，用于识别已被覆盖的请求
func _confirm_scene_change(path: String, generation: int) -> Error:
	if generation != _request_generation:
		return ERR_SKIP
	var tree := get_tree()
	if tree.current_scene == null or current_scene_path != path:
		await tree.scene_changed
	if generation != _request_generation or current_scene_path != path:
		return ERR_SKIP
	scene_changed.emit(path)
	return OK

## 检查场景路径；空路径或无法作为 [PackedScene] 加载时返回 [code]false[/code]。 [br][br]
## [param path] : 目标资源路径
func _is_valid_scene_path(path: String) -> bool:
	if path.is_empty() or not ResourceLoader.exists(path, "PackedScene"):
		push_error("[UFrameSceneService] 场景不存在：%s" % path)
		return false
	return true

## 清理叠加场景记录；主场景切换会统一释放节点，本方法只清理持有的引用。
func _clear_overlay_records() -> void:
	_overlay_scenes.clear()
#endregion
