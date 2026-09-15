# UFrame 0.4

UFrame 是面向 Godot 4.7 的轻量 2D 游戏基础插件。它只注册一个 `UFrame` Autoload；其余能力是可选服务、局部组件或 Resource。

本 README 随插件目录独立分发，包含安装、配置、组合边界和主要公共用法。

## 设计边界

| 区域 | 负责 | 明确不负责 |
|---|---|---|
| `core/` | 游戏运行时入口、低频跨系统事件、内容注册 | EditorPlugin、实体战斗与 UI |
| `services/` | 跨场景且确实需要全局唯一的能力 | 玩家局部状态 |
| `components/` | 可挂载到实体的局部规则 | 项目专属画面与物品定义 |
| `resources/` | 可序列化的静态配置与存档数据 | 场景树生命周期 |

框架不再提供 Godot 已有等价 API 的 `MathUtil`、`ColorUtil`、`NodeUtil`、`TimeUtil` 或自制 Easing；直接使用引擎原生函数更短、更快，也更容易查文档。

所有公开全局类都使用 `UFrame*` 前缀，降低插件与宿主项目、其他插件发生全局类名冲突的概率。

## 场景优先的组件组合

UFrame 的推荐用法不是在 `_ready()` 中把实体拼出来，而是让场景树直接表达架构：

```text
Player (CharacterBody2D)       # Entity：可复用玩家场景
├── HealthComponent           # Component：UFrameHealth
├── TeamComponent             # Component：UFrameTeam
├── HurtboxComponent          # Component：UFrameHurtbox2D
│   └── CollisionShape2D
├── BehaviorManager           # 并行行为容器：UFrameBehaviorManager
│   ├── Movement              # UFrameBehavior 子类
│   └── DamageFeedback
└── StateMachine              # 互斥状态容器：UFrameStateMachine
	├── Idle                  # UFrameState 子类
	├── Run
	└── Air
```

- 稳定存在且需要 Inspector 配置的实体、组件、行为、状态、碰撞体和对象池写入 `.tscn`；
- 物品、掉落表等静态数据写入 `.tres`；
- 子弹、敌人、粒子、伤害数字和洗牌后的重复 Card View 等数量、身份或生命周期由运行时决定的对象，通过 PackedScene 或对象池生成；
- Autoload 只保留真正跨场景且全局唯一的服务，不充当所有实体的容器。

这种方式是向 ECS 思维过渡的“节点组件组合”：规则被拆成可独立挂载的组件，实体由组合产生，而不是依靠庞大的继承树。它刻意不冒充数据导向的完整 ECS，因此不需要额外的 World、Archetype 或查询框架，也保持了 Godot 初学者熟悉的场景工作流。

## 安装

只需把整个插件目录复制到：

```text
res://addons/uframe/
```

然后在 **项目设置 → 插件** 中启用 UFrame，不需要手动创建节点、Autoload 或项目设置，也不需要重启编辑器。首次启用会自动：

1. 注册唯一的 `UFrame` Autoload；
2. 在 **项目设置 → UFrame** 中补齐模块开关和日志设置；
3. 保留宿主项目已经存在的全部 UFrame 设置，不用默认值覆盖开发者选择。

编辑器关闭、重启或插件脚本重载不会撤销这些配置。只有开发者在插件面板中明确禁用 UFrame 时，插件才移除仍指向自身运行时脚本的 `UFrame` Autoload；模块设置会保留，方便之后重新启用。

若宿主已经拥有其他路径的同名 `UFrame` Autoload，插件会给出警告，并且在启用、禁用和重启过程中都不会覆盖或删除它。卸载文件前应先在插件面板中禁用 UFrame。

## 可选模块

在 **项目设置 → UFrame → Modules** 中开关模块，重新运行后生效：

| 设置 | 默认 | 入口 | 单一职责 |
|---|---:|---|---|
| registry | 开 | `UFrame.registry` | ID → 内容映射 |
| save | 开 | `UFrame.save` | Resource 存档与中断恢复 |
| audio | 开 | `UFrame.audio` | BGM 与非空间音效播放器复用 |
| scene | 开 | `UFrame.scenes` | 主场景和叠加场景生命周期 |
| transition | 开 | `UFrame.transitions` | 全屏淡入淡出；加载委托给 SceneService |
| input | 关 | `UFrame.input` | 短时输入缓冲与本服务查询层锁定 |
| camera | 关 | `UFrame.camera` | Camera2D trauma 震动合成 |

表中是插件首次补充设置时的默认值。Transition 的场景切换功能依赖 Scene 模块，单独的遮罩淡入淡出不依赖场景加载。

禁用模块时对应字段为 `null`：

```gdscript
if UFrame.camera:
	UFrame.camera.add_trauma(0.2)
```

### 场景切换与过渡

需要等待新场景真正就绪时，使用带确认的方法；它有有限等待和错误返回，不会无限卡住：

```gdscript
var error := await UFrame.scenes.change_scene_confirmed("res://levels/level_01.tscn")
if error != OK:
	push_error("场景切换失败：%d" % error)
```

需要黑幕淡入淡出时直接使用过渡服务。即使加载失败，遮罩也会恢复透明：

```gdscript
var succeeded := await UFrame.transitions.change_scene("res://levels/level_01.tscn")
```

只想提交切换、不等待结果时，才使用同步的 `UFrame.scenes.change_scene()`。

场景就绪由 Godot 原生 `SceneTree.scene_changed` 确认；较新请求覆盖旧请求时，旧请求返回 `ERR_SKIP`。`current_scene_path` 直接反映当前主场景，包括使用原生 API 切换的场景；替换间隙可能为空。

存档读取失败时 `UFrame.save.load()` 返回 `null`。调用方决定创建哪个新游戏数据类型，例如 `var data := UFrame.save.load("slot_1") as MySaveData`，然后在 `data == null` 时创建 `MySaveData.new()`。

## 高频局部组件

### 生命与碰撞

```text
Player (CharacterBody2D)
├── HealthComponent       # 脚本类 UFrameHealth
└── HurtboxComponent      # 脚本类 UFrameHurtbox2D
	└── CollisionShape2D
```

`UFrameHealth.take_damage()` 返回实际扣除量。`UFrameHurtbox2D` 只有在伤害真正生效后才确认命中；高频反馈监听本地 signal，不会强制广播到全局 EventBus：

```gdscript
$Bullet.hit_confirmed.connect(_spawn_hit_effect)
$HealthComponent.damaged.connect(_on_damaged)
```

双方都挂有 `UFrameTeam` 时，Hurtbox 默认会过滤友军；任一方没有 Team 时仍保持独立可用。池化实体重新取出时可调用 `UFrameHealth.reset()`，它会补满生命并清除旧无敌计时。

命中后的实体生命周期由实体脚本处理：监听 `hit_confirmed` 后调用 `queue_free()`、归还对象池或继续穿透。Hitbox 不再提供 `destroy_on_hit`；关闭单次命中限制时也不会保存命中集合。设置最大生命并补满、切换 Health 的 Stats 依赖时，实际 HP 变化会发送 `hp_changed`。

### 对象池

```gdscript
var bullet := $BulletPool.acquire()
if bullet:
	bullet.launch(global_position, direction, self)

$BulletPool.release(bullet)
```

`UFramePool` 会拒绝重复归还和外部对象，并清理被外部释放的实例。归还时只将场景根节点设为 `PROCESS_MODE_DISABLED` 并隐藏；使用 Godot 默认配置时，后代碰撞对象会通过 `DISABLE_MODE_REMOVE` 自动退出物理模拟，取出时自动恢复，不需要改写碰撞层、遮罩或 Area 配置。创建、取出、归还钩子与对应信号都是同步生命周期事务；事务结束前不能再次修改同一个 Pool，需要继续 `acquire()`、`release()` 或 `clear()` 时应使用 `call_deferred()`。

池化场景的根节点和后代应保留默认的 `Process Mode = Inherit`，`CollisionObject2D/3D` 应保留默认的 `Disable Mode = Remove`。含有画面内容时，场景根节点应为 `CanvasItem`（例如 `Node2D`、`Control`）或 `Node3D`，这样根节点隐藏会自然作用于可视后代。需要停止音频、计时器、粒子或重置游戏数据时，实现 `_on_pool_acquire()` 与 `_on_pool_release()`。

容量在 Inspector 中直接配置：

- `Initial Size`：场景启动时预热多少个实例；
- `Maximum Size = 0`：不限制总实例数，也就是关闭上限；
- `Maximum Size > 0`：限制池拥有的总实例数；满载且没有空闲实例时，自动完整停用最早活跃实例并发出 release 信号，随后立即复用同一 Node。

“最早”指当前仍在使用的实例中，最近一次成功 `acquire()` 最早者；复用后会成为最新。有限容量意味着活跃生命周期允许被提前结束；不能中断的任务对象应使用 `Maximum Size = 0`。带有延迟归还操作的对象必须在 release 钩子中取消旧请求，避免旧回调影响复用后的新生命周期。

### 唯一背包模型

`UFrameInventory` 同时提供简单数量 API 和格子 API，不需要第二个背包脚本：

```gdscript
var inventory := UFrameInventory.new()
inventory.slot_count = 64
inventory.set_stack_limit(&"material", 64)
inventory.set_stack_limit(&"potion", 16)
inventory.set_stack_limit(&"sword", 1)

inventory.add_item(&"potion", 20)
inventory.move_stack(0, 8)
inventory.split_half(8, 9)
inventory.sort_and_merge()
```

集中掉落或装载大量物品使用批量入口，只扫描一次背包建立本次操作所需的索引：

```gdscript
var requested: Dictionary[StringName, int] = {&"potion": 20, &"sword": 2}
var added := inventory.add_items(requested)
# 容量不足时允许部分加入，调用方使用 added 判断剩余掉落。
```

批量请求按字典顺序分配空格；每个变化格子只通知一次，整体只通知一次。整理也只通知实际变化的格子，已经整理好时不发送变化信号。

缩容、降低堆叠上限和整理会先检查现有内容能否安全容纳；检测到丢物风险时拒绝修改。`set_slots()` 会验证容量内的保存条目后整体替换，`get_count()` 使用缓存；一次批量消耗只发送一次整体变化信号。

宿主项目可以另外创建静态物品 Resource 和格子 View；它们只负责内容定义与显示，不保存背包内容或移动规则，因此不会形成第二套 Inventory。

### 状态机与行为

- `UFrameStateMachine` + `UFrameState`：唯一节点式状态机；直接挂在实体下，状态作为它的子节点。状态机先收集全部状态，再注入状态机与实体并调用一次 `on_setup()`，适合缓存强类型引用或校验长期依赖；`on_enter()` 仍在每次进入状态时执行。状态机自动转发普通帧与物理帧更新，每个状态只需覆写需要的回调。使用 `connect_state_changed()` 连接状态回调，无论连接发生在初始化前后都会同步到初始状态。
- `UFrameBehaviorManager` + `UFrameBehavior`：Manager 直接挂在实体下，Behavior 只放在 Manager 下，节点名就是查询 ID。Manager 不进入逐帧循环，只负责整理层级、注入实体引用和统一启停；行为只需覆写需要的回调，禁用后停止两种帧更新。

```gdscript
var movement := $BehaviorManager.get_behavior(&"Movement")
$BehaviorManager.set_behavior_enabled(&"Movement", false)
```

状态切换回调（`on_enter`、`on_exit`、`state_changed`）内不允许同步再次切换，需要继续转换时使用 `state_machine.change_state.call_deferred(&"next_state")`。Behavior 直接设置 `enabled`，不再提供同义的 `set_enabled()`。
- `UFrameStats` + `UFrameStatModifier`：按属性缓存计算结果；运行期加入限时修改器后按需进入帧循环。单项变化使用 `add_modifier()` / `remove_modifier()`；初始化装备、读档或同帧到期等集中变化使用 `add_modifiers()` / `remove_modifiers()`，每个受影响属性只排序、重算并发送一次 `stat_changed`。同一个 Modifier Resource 实例不能重复加入，需要独立层数时应为每层创建或复制独立实例。修正生效期间视为不可变；需要修改字段时先移除、修改，再重新加入。生命周期或 `stat_changed` 监听器若要继续增删同一个 Stats，应使用 `call_deferred()`。

```gdscript
var modifiers: Array[UFrameStatModifier] = [weapon_modifier, buff_modifier]
var added_count := $Stats.add_modifiers(modifiers)
```

`base_stats` 仍可在 Inspector 配置。运行时读取返回只读快照：单项修改使用 `$Stats.set_base_stat("speed", 200.0)`；整体替换使用 `$Stats.base_stats = {...}`。组件复制输入字典，避免外部引用绕过缓存失效。基础值与修正的同步通知期间，后续修改都需要 `call_deferred()`。未配置属性的默认值仅用于本次查询，不进入共享缓存。

移除修正由 Stats 从基础值重新计算，已删除无法可靠支持全部运算的 `StatModifier.revert()`。

## 数据 Resource

- `UFrameResourceData`：物品、武器等静态数据的可选基类。
- `UFrameLootEntry` + `UFrameLootTable`：加权掉落、空掉落和保底。
- `UFrameRunData`：存档基类；正式项目应创建自己的强类型子类。

`UFrameLootTable` 是纯配置，不在共享 Resource 内保存保底计数。调用者显式传回 `miss_count`：

```gdscript
var result := loot_table.roll(miss_count)
miss_count = result.miss_count
if result.count > 0:
	inventory.add_item(result.content_id, result.count)
```

这样多个敌人、玩家或掉落来源可以共享一张表，却各自拥有独立保底进度。

## 性能约束

- 无敌计时、输入缓冲和相机震动只在激活期间进入帧循环；运行期加入限时属性后才启用 Stats 计时，批量修正按属性合并排序、重算和变化通知。
- 高频战斗使用局部 signal；`UFrame.events` 只用于关卡完成等低频跨系统消息。
- 对象池的计数查询为 O(1)，普通空闲复用和正常满载溢出都不扫描全池；满载时直接回收最早活跃实例，只有内部容量账本出现矛盾时才执行完整修复扫描。
- 对象池不会自动猜测业务状态，实例自行实现池生命周期钩子；`Maximum Size = 0` 关闭容量回收，正数触顶时使用固定的最早实例回收规则。
- Registry 只保存调用方注册的非空值，不扫描场景树；目录扫描只在显式调用时执行。
- UI、图标、粒子和玩法逻辑全部留在宿主项目中，插件运行时不会加载它们。

## 安装验证

启用后可在任意场景脚本中进行最小检查：

```gdscript
func _ready() -> void:
	assert(UFrame.events != null)
	assert(UFrame.is_module_enabled("registry") == (UFrame.registry != null))
```

同时确认 **项目设置 → 自动加载** 中只有一个 `UFrame`，并在 **项目设置 → UFrame** 中按当前项目需要关闭不使用的模块。宿主项目若提供自动化测试，应把实际启用组合、场景切换、存档和池化生命周期纳入自己的回归入口。
