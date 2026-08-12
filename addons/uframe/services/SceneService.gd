extends Node

## 可选场景管理服务
##
## 通过 [code]UFrame.scenes[/code] 使用，统一管理主场景切换与叠加场景。
## [method change_scene] 立即提交普通切换，[method change_scene_async] 在线程中加载大场景。
## 本服务不负责画面遮罩；需要淡变效果时由 [UFrameTransition] 编排。
## 只有新场景真正成为 [member SceneTree.current_scene] 后才发出 [signal scene_changed]。
class_name UFrameSceneService

#region 常量
## 场景切换确认的最大等待帧数。
## Godot 在帧边界完成场景替换，因此同步切换需要有限帧数确认最终结果。
const SCENE_CONFIRMATION_MAX_FRAMES := 16
#endregion

#region 信号
## 请求通过路径验证、即将提交时发出。
## [param from] 是当前主场景路径，[param to] 是目标主场景路径。
signal scene_changing(from: String, to: String)

## 新场景已经成为 [member SceneTree.current_scene] 时发出。
## [param new_scene] 是已经确认生效的新主场景路径。
signal scene_changed(new_scene: String)
#endregion

#region 运行时状态
## 当前主场景路径，仅在确认切换完成后更新。
var current_scene_path := ""

## 叠加场景表：场景路径 → 当前主场景下的实例。
var _overlay_scenes: Dictionary[String, Node] = {}

## 场景请求代次；新请求会使仍在等待的旧请求返回 [constant ERR_SKIP]。
var _request_generation := 0
#endregion

#region 生命周期
func _ready() -> void:
	var current := get_tree().current_scene
	if current:
		current_scene_path = current.scene_file_path
#endregion

#region 主要方法
## 提交普通场景切换并返回 Godot [code]Error[/code]；成功提交后可等待 [signal scene_changed]。
func change_scene(path: String) -> Error:
	var request := _submit_scene_change(path)
	var error: Error = request.error
	if error == OK:
		_confirm_scene_change.call_deferred(path, int(request.generation))
	return error

## 切换并等待目标真正成为 [member SceneTree.current_scene]，返回最终 Godot [code]Error[/code]。
func change_scene_confirmed(path: String) -> Error:
	var request := _submit_scene_change(path)
	var error: Error = request.error
	if error != OK:
		return error
	return await _confirm_scene_change(path, int(request.generation))

## 在线程中加载并切换场景；返回 [constant OK] 表示新场景已经成为当前主场景。
## [param on_progress] 是可选加载进度回调，参数范围为 [code]0.0[/code] 到 [code]1.0[/code]。
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

## 重新加载当前主场景；没有可用路径时返回 [constant ERR_DOES_NOT_EXIST]。
func reload_current() -> Error:
	var path := current_scene_path
	if path.is_empty() and get_tree().current_scene:
		path = get_tree().current_scene.scene_file_path
	return change_scene(path) if not path.is_empty() else ERR_DOES_NOT_EXIST

## 在当前主场景下添加叠加场景；同一路径已有有效实例时直接返回原实例。
## 路径无效、加载失败或没有当前主场景时返回 [code]null[/code]。
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

## 移除叠加场景；目标存在时排队释放并返回 [code]true[/code]。
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
## 提交普通场景切换，返回 [code]error[/code] 与本次请求的 [code]generation[/code]。
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

## 在有限帧数内确认目标已经成为当前场景；请求被覆盖时返回 [constant ERR_SKIP]。
func _confirm_scene_change(path: String, generation: int) -> Error:
	# 场景切换在帧边界提交；有限轮询兼容不同后端，也确保失败时能返回明确错误
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

## 判断当前主场景是否匹配目标路径。
func _current_scene_matches(path: String) -> bool:
	var current := get_tree().current_scene
	return current != null and current.scene_file_path == path

## 检查场景路径；空路径或无法作为 [PackedScene] 加载时返回 [code]false[/code]。
func _is_valid_scene_path(path: String) -> bool:
	if path.is_empty() or not ResourceLoader.exists(path, "PackedScene"):
		push_error("[UFrameSceneService] 场景不存在：%s" % path)
		return false
	return true

## 清理叠加场景记录；主场景切换会统一释放节点，本方法只清理持有的引用。
func _clear_overlay_records() -> void:
	_overlay_scenes.clear()
#endregion
