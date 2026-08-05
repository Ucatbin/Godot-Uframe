# UFrame Godot 原生化与轻量化审查

审查日期：2026-08-05

验证版本：Godot 4.7.stable.official.5b4e0cb0f

## 结论

UFrame 的组件化方向是成立的，Inventory、战斗组件、状态机、行为、过渡和跨系统事件等高层语义也没有可以直接替代的 Godot 原生节点。

当前主要问题不是“所有自定义代码都多余”，而是少数模块同时维护了 Godot 已经维护的第二份状态，或者为了兼容过宽的使用方式加入了递归扫描、轮询和全局管理。应继续采用以下边界：

1. 引擎状态是唯一事实来源，不缓存可以直接查询的场景树状态。
2. 优先使用 `process_mode`、原生信号、音频总线、复音播放和类型化节点导出。
3. 局部玩法能力优先作为场景组件，不默认升级为全局服务。
4. 框架只兜底明确支持的组合方式，不为主动修改默认生命周期的节点增加隐式修复。

## 已完成：Pool 原生化

文件：[`PoolComponent.gd`](addons/uframe/components/PoolComponent.gd)

已经删除：

- 6 个碰撞状态元数据键。
- 2D/3D 碰撞层、遮罩和 Area 状态的手动保存与恢复。
- 每次创建、归还和取出时对整棵场景树的递归扫描。

现在归还对象只执行：

```gdscript
instance.process_mode = Node.PROCESS_MODE_DISABLED
instance.visible = false
```

重新取出时恢复 `PROCESS_MODE_INHERIT` 和可见性。Godot 默认的 `CollisionObject2D/3D.disable_mode = DISABLE_MODE_REMOVE` 会让继承处理模式的后代自动退出物理空间，并在恢复时重新加入；碰撞层和 Area 配置始终保持原值。

支持边界：

- 根节点与需要一同停用的后代使用默认 `Process Mode = Inherit`。
- 碰撞节点使用默认 `Disable Mode = Remove`。
- 有画面内容的池化场景根节点必须继承 `CanvasItem` 或 `Node3D`。
- `Maximum Size = 0` 表示无限扩容；正数容量满载时始终结束并复用最早活跃实例，不再维护溢出策略分支。
- 音频、粒子、计时器和游戏数据通过 `_on_pool_release()` / `_on_pool_acquire()` 重置。

测试现在直接验证碰撞 RID 退出并恢复物理空间，而不是验证碰撞层被改成 `0`。

## P1：发布插件前应修改

### 1. EditorPlugin 使用了错误的持久配置生命周期

文件：[`UFramePlugin.gd:37`](addons/uframe/UFramePlugin.gd#L37)

Autoload 当前在 `_enter_tree()` 注册、在 `_exit_tree()` 删除。插件重载或编辑器关闭也会退出树，不等于用户禁用插件；现有同路径 Autoload 还会被当作当前实例拥有。

应将 Autoload 注册和移除分别放入 `_enable_plugin()` 与 `_disable_plugin()`。项目设置的编辑器元数据可以继续在 `_enter_tree()` 中补充，并且只在实际改变设置时调用 `ProjectSettings.save()`。

### 2. SceneService 手工重建了 `SceneTree.scene_changed`

文件：[`SceneService.gd:13`](addons/uframe/services/SceneService.gd#L13)、[`SceneService.gd:176`](addons/uframe/services/SceneService.gd#L176)

删除 `SCENE_CONFIRMATION_MAX_FRAMES` 和最多 16 帧的轮询，改为等待：

```gdscript
await get_tree().scene_changed
```

仍保留请求 generation 检查，以拒绝已经被新请求覆盖的旧操作。

同时删除 `current_scene_path` 缓存，直接从 `get_tree().current_scene.scene_file_path` 查询；`reload_current()` 使用原生 `reload_current_scene()`。框架自定义的同名 `scene_changed(String)` 应删除或改名，避免与原生信号混淆。

### 3. AudioService 手写了 Godot 已有的复音系统与总线音量

文件：[`AudioService.gd:51`](addons/uframe/services/AudioService.gd#L51)、[`AudioService.gd:134`](addons/uframe/services/AudioService.gd#L134)、[`AudioService.gd:195`](addons/uframe/services/AudioService.gd#L195)

用一个 `AudioStreamPlayer + AudioStreamPolyphonic` 取代 `_sfx_pool`。`AudioStreamPlaybackPolyphonic.play_stream()` 已支持不同音频流、独立音量、音高、总线和播放 ID。

当前 `master_volume/sfx_volume/bgm_volume` 与 `_apply_volume()` 也在维护第二套音频混音状态，应委托给 `AudioServer` 的 Master、Music、SFX 总线。现有代码在 BGM 淡变期间修改音量会杀死 Tween，使后续切歌回调丢失，这是确定性行为错误。

### 4. Behavior 的 disabled 没有关闭完整的节点处理

文件：[`Behavior.gd:122`](addons/uframe/components/behaviors/Behavior.gd#L122)

`set_process(false)` 和 `set_physics_process(false)` 不会关闭 `_input()`、`_unhandled_input()` 等回调。应与 Pool 使用同一 Godot 逻辑：

```gdscript
process_mode = Node.PROCESS_MODE_INHERIT if _behavior_entered else Node.PROCESS_MODE_DISABLED
```

边界是 Behavior 的子节点属于该行为并保持 `Process Mode = Inherit`。

### 5. InputService 的“全局锁定”并不全局

文件：[`InputService.gd:55`](addons/uframe/services/InputService.gd#L55)、[`InputService.gd:73`](addons/uframe/services/InputService.gd#L73)

锁定只影响 `UFrame.input` 的转发方法，直接使用 `Input`、`_input()` 或 `_unhandled_input()` 的代码仍会收到输入，当前示例也会绕过它。

删除原生 Input 转发和“全局锁”承诺。保留输入缓冲算法，但将其改为玩家/控制器下的局部 `UFrameInputBuffer` 组件；这也能避免多玩家共同消费同一个动作缓冲。

### 6. Stats 限时修正存在生命周期错误

文件：[`StatComponent.gd:50`](addons/uframe/components/StatComponent.gd#L50)、[`StatComponent.gd:77`](addons/uframe/components/StatComponent.gd#L77)

- 入树前添加限时修正时，`_ready()` 会再次无条件停止处理，使修正永久存在。
- 同一个 Modifier 实例可以重复加入数组，但计时表以该 Resource 为唯一键，剩余副本可能永不到期。

`_ready()` 应根据计时表决定是否处理，并拒绝重复添加同一个 Modifier 实例。需要叠层时由调用者传入 `duplicate()` 后的新实例。

### 7. Health 与 Stats 同时拥有最大生命值

文件：[`HealthComponent.gd:38`](addons/uframe/components/HealthComponent.gd#L38)、[`HealthComponent.gd:159`](addons/uframe/components/HealthComponent.gd#L159)

绑定 Stats 后，公开的 `health.max_hp` 与实际使用的 `stats.max_hp` 可能不同步，上限变化也没有完整同步 HP 与信号。

建议删除 Health 内的 Stats 路径、缓存和绑定方法，让 Health 独占 `max_hp`。需要属性联动时，由项目代码或专用适配 Behavior 监听 `stat_changed` 后调用 `health.set_max_hp()`。

### 8. Hitbox 越权管理实体生命周期

文件：[`HitboxComponent.gd:24`](addons/uframe/components/HitboxComponent.gd#L24)、[`HitboxComponent.gd:48`](addons/uframe/components/HitboxComponent.gd#L48)

删除 `destroy_on_hit`、Hitbox 对父节点的 `queue_free()` 以及 Hitbox 自身的 `_on_pool_acquire()`：

- Hitbox 不应决定实体销毁还是归还池。
- Pool 只调用池化场景根节点的钩子，常见的子 Hitbox 钩子不会被调用。
- 实体根监听 `hit_confirmed` 后决定销毁/回收，并显式调用 `reset_hits()`，现有竞技场示例已经采用这种边界。

### 9. Inventory 的两条非法输入路径会违反事务语义

文件：[`InventoryComponent.gd:241`](addons/uframe/components/InventoryComponent.gd#L241)、[`InventoryComponent.gd:314`](addons/uframe/components/InventoryComponent.gd#L314)

- `place_stack()` 收到空 ID 或非正数量时返回 `{}`，看起来像全部放入，实际什么都没有发生；应返回原始堆叠副本。
- `set_slots()` 会静默忽略容量外的非 Dictionary 值；文档承诺非法数据整体拒绝，应先完整验证再提交。

### 10. 通用 SaveService 不应返回特定存档类型

文件：[`SaveService.gd:72`](addons/uframe/services/SaveService.gd#L72)

服务声明接受任意 Resource，但加载全部失败时返回 `UFrameRunData.new()`，会掩盖损坏/缺失并产生错误类型。应返回 `null`，默认存档由具体游戏创建。

临时档、主档、备份档的事务提交和 `CACHE_MODE_IGNORE` 应保留。

## P2：建议删减或收紧

### 框架代码

- [`ResourceData.gd`](addons/uframe/resources/ResourceData.gd)：只有掉落示例继承，`icon/tags/tier` 和查询方法均未使用。将真正需要的字段移到示例 Resource 后删除公共基类。
- [`RunData.gd`](addons/uframe/resources/RunData.gd)：SaveService 已能保存任意 Resource；将版本、时间戳和默认数据交给具体游戏，删除 SaveService 的 `touch()` 特判。
- [`StatModifier.gd:60`](addons/uframe/resources/StatModifier.gd#L60)：`revert()` 无调用且无法安全反转 Override、负乘数和 `PERCENT = -1`，直接删除；Stats 本来就是删除后重新计算。
- [`State.gd:12`](addons/uframe/components/state_machine/State.gd#L12)、[`StateMachine.gd:29`](addons/uframe/components/state_machine/StateMachine.gd#L29)：`state_name` 与 `Node.name` 重复，`_states` 又缓存同一棵节点树。若状态固定且数量很少，直接以直属节点名查询能删除第二份状态；这是 API 迁移项，不是立即错误。
- [`BehaviorManager.gd:43`](addons/uframe/components/behaviors/BehaviorManager.gd#L43)：按名称获取行为可使用直属节点查询，不必每次遍历；初始子节点也会触发原生 `child_entered_tree`，可删除重复绑定路径。
- [`HurtboxComponent.gd:16`](addons/uframe/components/HurtboxComponent.gd#L16)：Godot 4 可直接导出类型化 `UFrameHealth`/`UFrameTeam` 节点，逐步淘汰 NodePath + 手动解析的 Godot 3 风格。
- [`Registry.gd:75`](addons/uframe/core/Registry.gd#L75)：项目资源目录扫描改用 `ResourceLoader.list_directory()`，更符合导出后 `res://` 资源语义；Registry 的分类与稳定 ID 主体保留。
- [`UFrame.gd:22`](addons/uframe/core/UFrame.gd#L22)：`ready_completed` 没有消费方，且 Autoload 初始化完全同步；删除，未来真正出现异步初始化时再引入可查询状态。
- [`CameraService.gd`](addons/uframe/services/CameraService.gd)：震动算法应保留，但更适合作为 Camera2D 的局部子组件。这样可以删除全局 Group 查找、相机引用和多 Viewport 冲突。
- [`LootTable.gd`](addons/uframe/resources/LootTable.gd)：没有 Godot 原生替代，但只服务于示例和测试。若基础插件继续收紧，可整体移到 `examples/loot/`。

### 示例代码

- [`example_ui.gd`](examples/common/example_ui.gd)：运行时创建并逐控件覆盖 StyleBox，改为公共 Theme `.tres` 与 `theme_type_variation`，让编辑器直接显示最终样式。
- [`burst_effect.gd`](examples/common/burst_effect.gd)：GDScript 逐粒子更新和绘制应改为 one-shot `GPUParticles2D` 或 `CPUParticles2D`，继续池化发射器即可。
- [`loot_demo.gd`](examples/loot/loot_demo.gd)：向全局 Registry 注册场景局部数据后没有注销。若用于演示 Registry，应在退出时注销；否则使用本地 ID Dictionary。
- [`platformer_player.gd`](examples/platformer/platformer_player.gd)：同时维护 UFrame 输入缓冲和本地缓冲，示例应明确只展示一种推荐方式。
- [`loot_demo.gd:47`](examples/loot/loot_demo.gd#L47)：只为 Esc 和鼠标位置常驻 `_process()`，改用 `_unhandled_input()` / `InputEventMouseMotion`，或只在拖拽期间启用处理。

## 应保留的设计

- `EventBus`：低频跨系统动态事件有明确价值；局部和高频通信继续使用原生 signal，不再增加复杂订阅对象。
- `Registry` 主体：内容分类、稳定语义 ID 和覆盖通知不是 ResourceLoader 的重复功能。
- `Inventory` 的格子事务、堆叠规则与 `_totals` 缓存：Godot 没有原生 Inventory，64 格频繁查询也值得缓存。
- 状态机和 Behavior 的“节点即组成部分”设计：符合 Godot 场景组合，只需删除重复索引/状态并正确使用生命周期。
- `TransitionService`：Tween + CanvasLayer + ColorRect 是有效的高层功能，Godot 没有一条原生淡变切场景 API。
- `SceneService` 的线程加载进度与唯一叠加场景管理：在原生 ResourceLoader/SceneTree 之上提供了新语义。
- `SaveService` 的事务恢复流程：ResourceSaver 没有提供等价的临时档/备份恢复。
- Camera trauma/FastNoise 算法：没有原生等价，只应调整为局部组件。
- Health、Team、Hitbox、Hurtbox 的基本职责分离，以及蜘蛛纸牌的规则/View 分离。

## 推荐实施顺序

1. 修正 EditorPlugin 生命周期。
2. SceneService 改用 `SceneTree.scene_changed`，删除场景路径缓存。
3. AudioService 改用 `AudioStreamPolyphonic` 和 AudioServer 总线。
4. Behavior 改用 `process_mode`；输入缓冲与相机震动局部化。
5. 修复 Stats、Health、Hitbox、Inventory 和 Save 的确定性边界问题。
6. 删除 ResourceData、RunData、StatModifier.revert 等无消费或错误 API。
7. 最后迁移示例 Theme、原生粒子和输入事件，避免在框架 API 仍变化时重复调整展示层。

## 官方依据

- [CollisionObject2D DisableMode](https://docs.godotengine.org/en/4.5/classes/class_collisionobject2d.html)
- [CollisionObject3D DisableMode](https://docs.godotengine.org/en/4.4/classes/class_collisionobject3d.html)
- [SceneTree.scene_changed](https://docs.godotengine.org/en/stable/classes/class_scenetree.html)
- [AudioStreamPolyphonic 4.7](https://docs.godotengine.org/en/4.7/classes/class_audiostreampolyphonic.html)
- [EditorPlugin Autoload 生命周期](https://docs.godotengine.org/en/stable/tutorials/plugins/editor/making_plugins.html)
- [ResourceLoader.list_directory](https://docs.godotengine.org/en/stable/classes/class_resourceloader.html)
- [Godot Theme](https://docs.godotengine.org/en/stable/classes/class_theme.html)
- [Godot Server 优化边界](https://docs.godotengine.org/en/latest/tutorials/performance/using_servers.html)
