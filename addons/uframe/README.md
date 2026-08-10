# UFrame 0.4

UFrame 是面向 Godot 4.7 的轻量 2D 游戏基础插件。它只注册一个 `UFrame` Autoload；其余能力是可选服务、局部组件或 Resource。

仓库内置四个可运行示例，参见 [`res://examples/README.md`](../../examples/README.md)。启动示例浏览器后可按 `1 / 2 / 3 / 4` 快速进入对应玩法。

## 设计边界

| 区域 | 负责 | 明确不负责 |
|---|---|---|
| `core/` | 插件入口、低频跨系统事件、内容注册 | 实体战斗与 UI |
| `services/` | 跨场景且确实需要全局唯一的能力 | 玩家局部状态 |
| `components/` | 可挂载到实体的局部规则 | 项目专属画面与物品定义 |
| `resources/` | 可序列化的静态配置与存档数据 | 场景树生命周期 |
| `examples/` | 具体玩法、UI、原生绘制特效 | 框架公共 API |

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

把整个目录复制到：

```text
res://addons/uframe/
```

然后在 **项目设置 → 插件** 中启用 UFrame。若宿主已经拥有其他路径的同名 `UFrame` Autoload，插件会警告且不会覆盖或删除它。

## 可选模块

在 **项目设置 → UFrame → Modules** 中开关模块，重新运行后生效：

| 设置 | 默认 | 入口 | 单一职责 |
|---|---:|---|---|
| registry | 开 | `UFrame.registry` | ID → 内容映射 |
| save | 开 | `UFrame.save` | Resource 存档与中断恢复 |
| audio | 开 | `UFrame.audio` | BGM 与非空间音效播放器复用 |
| scene | 开 | `UFrame.scenes` | 主场景和叠加场景生命周期 |
| transition | 开 | `UFrame.transitions` | 全屏淡入淡出；加载委托给 SceneService |
| input | 关 | `UFrame.input` | 短时输入缓冲与全局输入锁 |
| camera | 关 | `UFrame.camera` | Camera2D trauma 震动合成 |

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

需要黑幕淡入淡出时直接使用过渡服务。即使加载失败或超时，遮罩也会恢复透明：

```gdscript
var succeeded := await UFrame.transitions.change_scene("res://levels/level_01.tscn")
```

只想提交切换、不等待结果时，才使用同步的 `UFrame.scenes.change_scene()`。

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

### 对象池

```gdscript
var bullet := $BulletPool.acquire()
if bullet:
    bullet.launch(global_position, direction, self)

$BulletPool.release(bullet)
```

`UFramePool` 会拒绝重复归还和外部对象，并清理被外部释放的实例。归还时只将场景根节点设为 `PROCESS_MODE_DISABLED` 并隐藏；使用 Godot 默认配置时，后代碰撞对象会通过 `DISABLE_MODE_REMOVE` 自动退出物理模拟，取出时自动恢复，不需要改写碰撞层、遮罩或 Area 配置。

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

缩容、降低堆叠上限、读档与整理都采用事务规则：成功时完整提交，可能丢物时返回失败并保持原内容。`get_count()` 使用缓存；一次批量消耗只发送一次整体变化信号。

示例中的 `LootDemoItemData` 是静态物品 Resource，`InventorySlotButton` 是格子 View；二者都不保存背包内容或移动规则，因此不是第二套 Inventory 实现。

### 纯规则模型与 View：蜘蛛纸牌示例

蜘蛛纸牌展示了另一种常见边界：规则很多，但不应该为了显示 104 张牌而复制 104 份规则。

- 示例可在场景内选择单色、双色或四色，三档都使用标准的 104 张牌；开局固定 10 列，牌库可以再向每列发牌 5 次；
- 规则模型独立判断跨花色的单张接龙、同花色连续牌组拖拽、右键自动落牌的“同花色 → 异花色 → 空列”优先级、发牌限制、同花色 `K → A` 自动收组、8 组胜利与撤销恢复；
- 规则模型不引用 Label、Control、Tween 或粒子，因此可以用纯数据测试每一种移动；
- `spider_demo.tscn` 中直接存在三档难度按钮、固定的 10 个列挂载点，以及 Completed、牌库 HUD、CardLayer、DragLayer 和 FeedbackOverlay；这些稳定结构能在编辑器里直接查看；
- 洗牌后每张牌的身份、花色与位置才确定，因此 104 个 Card View 从一个 PackedScene 模板运行时实例化；View 只读取规则结果并显示花色，不自行决定一次移动是否合法；
- 撤销保存的是一次操作前的牌局快照，所以移动附带的翻牌、发牌和自动收组能作为一个整体恢复；
- 集中的 FeedbackOverlay 按需绘制有数量上限的蛛丝、光环和粒子，没有效果时停止 `_process()`；每张 Card View 都没有常驻 `_process()`。
- 合法移动只重排实际改变的两列；被覆盖卡牌只绘制顶部条，发牌共享一个入场调度 Tween，翻牌使用节点变换而不是逐帧重建牌面几何。

这里的重点不是把所有节点都静态写死，而是区分两类内容：固定结构写入场景，数量或身份由运行时决定的重复 View 从模板生成。这样既保留可读的场景树，也不会为了“看得见”而堆出数百份重复配置。

### 状态机与行为

- `UFrameStateMachine` + `UFrameState`：唯一节点式状态机；直接挂在实体下，状态作为它的子节点。状态机先收集全部状态，再注入状态机与实体并调用一次 `on_setup()`，适合缓存强类型引用或校验长期依赖；`on_enter()` 仍在每次进入状态时执行。状态机自动转发普通帧与物理帧更新，每个状态只需覆写需要的回调。使用 `connect_state_changed()` 连接状态回调，无论连接发生在初始化前后都会同步到初始状态。平台示例的 Idle、Run、Air 共享 `PlatformerState` 基类，分别真正执行移动、跳跃和重力逻辑，而不是空标签。
- `UFrameBehaviorManager` + `UFrameBehavior`：Manager 直接挂在实体下，Behavior 只放在 Manager 下，节点名就是查询 ID。Manager 不进入逐帧循环，只负责整理层级、注入实体引用和统一启停；行为只需覆写需要的回调，禁用后停止两种帧更新。

```gdscript
var movement := $BehaviorManager.get_behavior(&"Movement")
$BehaviorManager.set_behavior_enabled(&"Movement", false)
```
- `UFrameStats` + `UFrameStatModifier`：按属性缓存计算结果，限时修改器激活时才进入帧循环。

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

- 无敌计时、输入缓冲、限时属性与相机震动只在激活期间进入帧循环。
- 高频战斗使用局部 signal；`UFrame.events` 只用于关卡完成等低频跨系统消息。
- 对象池的计数查询为 O(1)，普通空闲复用不扫描全池；只有真正触顶时才清理失效引用并回收最早活跃实例。
- 对象池不会自动猜测业务状态，实例自行实现池生命周期钩子；`Maximum Size = 0` 关闭容量回收，正数触顶时使用固定的最早实例回收规则。
- Registry 只保存引用，不扫描场景树；目录扫描只在显式调用时执行。
- UI、图标、粒子和玩法逻辑全部留在示例或宿主项目中，插件运行时不会加载它们。

## 验证

```powershell
Godot_v4.7-stable_win64_console.exe --headless --path <project> res://tests/test_runner.tscn
Godot_v4.7-stable_win64_console.exe --headless --path <project> res://tests/scene_transition_source.tscn
Godot_v4.7-stable_win64_console.exe --headless --path <project> res://tests/scene_transition_source.tscn -- --async
Godot_v4.7-stable_win64_console.exe --headless --path <project> res://tests/scene_transition_source.tscn -- --spider
```

测试覆盖事件递归、背包事务、独立保底、阵营伤害过滤、组合实体后代碰撞、对象池失效实例、相机重绑定、真实场景过渡、输入缓冲、行为生命周期、音量更新、存档恢复，以及四个示例的场景组件结构。
