# UFrame 当前架构

文档状态：当前事实说明
对应版本：UFrame 0.4.0 / Godot 4.7
最后核对：2026-08-11

本文只描述仓库当前已经实现的职责、依赖与组合方式。目标源码、场景和自动化测试是最终事实来源。

## 设计目标

- 以 Godot 原生场景、节点、Resource 和 signal 为基础，不重建一套平行引擎。
- 稳定结构通过场景树显式组合，便于入门开发者查看和配置。
- 框架只提供跨项目可复用的规则；玩法、UI 和视觉保留在宿主项目或示例中。
- 全局服务保持少量且可选；局部能力优先作为实体组件。
- 没有活动时减少帧处理，高频路径避免全局广播和不必要扫描。

UFrame 是“节点组件组合 + 少量全局服务”，不是数据导向的完整 ECS。它为 ECS 思维提供职责拆分，但不增加 World、Archetype 或查询系统。

## 运行时拓扑

插件只注册一个 `UFrame` Autoload：

```text
UFrame
├── Events          # 始终创建
├── Registry        # 可选
├── Save            # 可选
├── Audio           # 可选
├── Scenes          # 可选
├── Transitions     # 可选
├── Input           # 可选
└── Camera          # 可选
```

- 编辑器入口：`addons/uframe/UFramePlugin.gd` 与 `plugin.cfg`。
- 游戏运行时入口：`addons/uframe/core/UFrame.gd`。
- EditorPlugin 在加载时补充缺失的 `uframe/*` 设置和编辑器显示元数据，只在用户明确启用或禁用插件时注册或移除 `UFrame` Autoload。
- 关闭编辑器或重载插件脚本不会移除 Autoload；禁用时保留模块设置，并且不会覆盖或删除其他路径的同名入口。
- 运行时入口始终创建 EventBus，再创建已启用模块，并把 SceneService 注入 TransitionService。
- 可选模块关闭后，对应 `UFrame.*` 字段为 `null`。

| 模块 | 新宿主项目默认 | 当前示例项目 | 访问入口 |
|---|---:|---:|---|
| EventBus | 始终开启 | 开 | `UFrame.events` |
| Registry | 开 | 开 | `UFrame.registry` |
| Save | 开 | 开 | `UFrame.save` |
| Audio | 开 | 开 | `UFrame.audio` |
| Scene | 开 | 开 | `UFrame.scenes` |
| Transition | 开 | 开 | `UFrame.transitions` |
| Input | 关 | 开 | `UFrame.input` |
| Camera | 关 | 开 | `UFrame.camera` |

表中“新宿主项目默认”来自 EditorPlugin 的缺省设置；仓库示例为了展示所有能力，在 `project.godot` 中显式开启了 Input 和 Camera。Transition 的场景切换功能依赖 SceneService，单独的遮罩淡入淡出不依赖场景加载。

## 目录职责与依赖方向

| 目录 | 当前职责 |
|---|---|
| `addons/uframe/core/` | 运行时门面、低频 EventBus、运行时 Registry |
| `addons/uframe/services/` | 跨场景且全局唯一的音频、场景、过渡、存档、输入缓冲和相机震动 |
| `addons/uframe/components/` | 挂到实体或关卡的生命、阵营、碰撞、属性、背包、对象池、状态与行为 |
| `addons/uframe/resources/` | 内容数据、存档数据、属性修正、掉落条目和掉落表 |
| `examples/` | 玩法、UI、视觉和框架组合展示 |
| `tests/` | 行为回归、场景组成与真实场景切换测试 |

当前调用与创建方向：

```text
examples / tests ──使用──> core、services、components、resources 的公共类型
UFrame runtime ──创建──> EventBus、Registry 与已启用 services
components ──按需协作──> 其他 components 或 resources
全部运行时代码 ──建立在──> Godot APIs
```

这些目录不是一条强制逐层依赖链：多数 Component、Service 和 Resource 可以独立使用 Godot API。插件运行时代码不引用 `examples/`。当前主要内部协作包括：

- UFrame 创建 EventBus、Registry 和可选服务。
- TransitionService 委托 SceneService 完成场景加载。
- Health 可以通过配置关系读取或写入 Stats 的 `max_hp`，但不会监听 Stats 的外部变化并自动同步当前 HP。
- Hurtbox 协调 Hitbox、Health 与可选 Team。
- Stats 应用 StatModifier。
- StateMachine 管理直属 State；BehaviorManager 管理直属 Behavior。
- LootTable 使用 LootEntry，保底计数由调用者持有。

## Core 与服务边界

| 能力 | 当前负责 | 明确边界 |
|---|---|---|
| EventBus | 低频跨系统事件、去重订阅、once 与取消订阅 | 不替代实体内高频 signal |
| Registry | “内容类型 + 内容 ID → 非空 Variant”运行时映射 | 不负责持久化或场景树发现 |
| Save | `user://saves/` 下任意 Resource 的保存、读取、删除与中断恢复 | 所有候选读取失败时当前固定返回新的 `UFrameRunData` |
| Audio | BGM、UI 和普通非空间音效复用 | 空间音频使用场景内原生 2D/3D 播放器 |
| Scene | 主场景切换、确认、线程加载与叠加场景 | 不负责画面遮罩 |
| Transition | 顶层遮罩、淡变与带遮罩的切场景流程 | 场景加载委托给 SceneService |
| Input | 短时动作缓冲和本服务查询层的锁定 | 不屏蔽原生 `Input` 或节点输入回调 |
| Camera | Camera2D 的 offset / rotation trauma 震动 | 不负责跟随、缩放和关卡取景 |

EventBus 与 Registry 始终保持小型语义：它们不引入订阅对象层级、全局实体查询或自动持久化。

## 局部组件边界

| 组件 | 当前职责 |
|---|---|
| `UFrameHealth` | 生命、伤害、治疗、死亡、无敌时间及按调用读取的可选 Stats 最大生命 |
| `UFrameTeam` | 阵营、友军和敌对关系 |
| `UFrameHitbox2D` | 伤害信息、单次激活命中记录，以及可选的命中后释放父实体 |
| `UFrameHurtbox2D` | 碰撞目标解析、双方都有 Team 时的友军过滤、Health 结算与命中确认 |
| `UFrameStats` | 基础属性、修正优先级、最终值缓存和运行期限时修正 |
| `UFrameInventory` | 单一背包模型，同时提供数量、格子、堆叠、移动、拆分与整理 API |
| `UFramePool` | PackedScene 预热、取出、归还、容量限制与根节点生命周期钩子 |
| `UFrameStateMachine` | 互斥状态收集、注入、切换和帧更新转发 |
| `UFrameBehaviorManager` | 可以并行启停的直属 Behavior 注入和统一控制 |

组件通过场景树组合，而不是要求实体继承大型框架基类。Health、Team 和 Hurtbox 保持分离；Hitbox 当前还保留 `destroy_on_hit` 这一可选兼容行为，以及供显式调用的池取出重置钩子。Pool 只调用池化场景根的钩子，因此 Hitbox 作为子节点时应由实体根转发重置或显式调用 `reset_hits()`。背包规则集中在一个 Inventory 模型，View 不保存第二套内容。

### Pool 当前语义

- `initial_size` 控制预热数量。
- `maximum_size = 0` 表示无限扩容。
- 正数容量满载且没有空闲项时，结束并复用最早活跃实例。
- 归还时停用实例根的 `process_mode`；根是 `CanvasItem` 或 `Node3D` 时还会隐藏，重新取出时恢复。
- 调用方必须让后代保持默认 `Process Mode = Inherit`、碰撞对象保持默认 `Disable Mode = Remove`；Pool 不会强制改写这些属性。
- 音频、粒子、Timer 与业务数据由实例根的 `_on_pool_acquire()` / `_on_pool_release()` 重置。
- Pool 生命周期钩子和信号同步执行；监听器若要继续修改同一个 Pool，必须延迟到当前事务结束后。

## State 与 Behavior 生命周期

推荐层级：

```text
Entity
├── StateMachine
│   ├── Idle
│   └── Air
└── BehaviorManager
	├── Movement
	└── DamageFeedback
```

StateMachine 在 `_ready()` 中一次性收集直属 State，先建立完整状态表，再注入状态机与父实体并调用一次 `on_setup()`，最后进入 `initial_state`。初始化后动态加入的 State 不会自动注册。

状态切换顺序：

```text
旧状态 on_exit()
→ 更新 current_state
→ 新状态 on_enter(data)
→ state_changed(previous, current)
```

状态机只向当前 State 转发普通帧和物理帧。`connect_state_changed()` 在初始化完成后连接时会立即同步当前状态，避免漏掉初始切换。

BehaviorManager 在入树时绑定已有直属 Behavior，并监听后来进入树的直属 Behavior。Behavior 等待所属实体 ready 后进入；启用、禁用和离树保证 `on_enter()` / `on_exit()` 成对，并同步自身两种帧处理状态。Behavior 节点名就是查询 ID。

## 场景组合

稳定、可配置、需要观察的结构写入 `.tscn`；数量、身份或生命周期在运行时才能确定的重复对象，从 PackedScene 或 Pool 生成。

以下是可选能力的组合示意，不表示当前每个实体都同时拥有全部节点：

```text
LevelRoot
├── LevelCamera
├── World
│   ├── WorldPool
│   ├── Goal / Platforms
│   └── Player (实体场景实例)
└── HUD (CanvasLayer)

Player
├── CollisionShape2D
├── VisualRoot
├── HealthComponent / TeamComponent / HurtboxComponent  # 按实体需要选择
├── BehaviorManager                                     # 可选并行行为
└── StateMachine                                        # 可选互斥状态
```

- 关卡根负责跨实体连接、关卡级依赖注入、HUD 和流程编排。
- 世界级 Pool 属于 World；固定关卡视角属于关卡，而不是 Player。
- 实体根保存共享状态和实体动作，Component、State、Behavior 保存局部规则。
- 可缩放视觉放入 `VisualRoot`，不改变碰撞体尺寸。
- Platformer、Loot 和 Spider 已对重要公开挂点使用 `%UniqueName`；Arena 仍主要使用 `$NodePath`。新示例按挂点稳定性选择，实体内部短且稳定的路径继续使用 `$NodePath`。
- 规则模型与 View 分离时，View 只发送输入意图并显示规则结果。

## Resource 数据

- `UFrameResourceData`：带稳定 ID、显示信息、标签等字段的内容数据基类。
- `UFrameRunData`：当前通用存档数据基类。
- `UFrameStatModifier`：属性名、运算、优先级、来源与可选持续时间。
- `UFrameLootEntry` / `UFrameLootTable`：加权掉落、空掉落与调用方持有的保底进度。

Resource 不负责 Node 生命周期。共享 LootTable 不保存某个敌人或玩家的运行时保底计数。

## 当前性能策略

- Health 无敌、Input 缓冲和 Camera 震动在没有活动时关闭帧处理；运行期添加限时 StatModifier 时才启用 Stats 计时，集中变化通过批量事务按属性统一提交。
- Behavior 只在进入后启用普通帧和物理帧回调。
- 高频战斗通过直接调用和局部 signal 结算，不经过 EventBus。
- Pool 普通空闲复用与正常满载溢出都不扫描完整所有权集合；触顶时直接处理最早活跃生命周期，只有账本矛盾才完整修复。
- Inventory 缓存物品总数；批量操作集中提交变化。
- Registry 不扫描场景树，目录扫描只在显式调用时发生。
- Camera 只有在缺少有效显式绑定时才按 `main_camera` Group 查找。
- 固定结构场景化；重复 View、Tween、粒子和池实例按需创建。

## 可运行示例

| 示例 | 主要展示 |
|---|---|
| Arena | Behavior、战斗组件、三个有限容量 Pool、局部信号与相机反馈 |
| Platformer | 显式 StateMachine、输入缓冲、真实物理结果驱动的状态与粒子反馈 |
| Loot | 唯一 Inventory 模型、Resource 数据、64 个同构格子 View 与 Save |
| Spider | 纯规则模型、数据驱动 Card View、局部布局、撤销和受限反馈预算 |

详细操作与节点说明见 [examples/README.md](examples/README.md)。

## 测试入口

`tests/test_runner.tscn` 是综合回归入口，成功时输出 `UFRAME_TESTS_OK` 并以退出码 `0` 结束。当前覆盖 Core、服务、组件、Resource、四个示例的场景组成及关键运行行为。

`tests/scene_transition_source.tscn` 验证真实 `current_scene`、场景服务、遮罩和过渡状态；支持 `--async`，以及 `--arena`、`--platformer`、`--loot`、`--spider` 目标参数。

```powershell
Godot_v4.7-stable_win64_console.exe --headless --path <project> res://tests/test_runner.tscn
Godot_v4.7-stable_win64_console.exe --headless --path <project> res://tests/scene_transition_source.tscn
Godot_v4.7-stable_win64_console.exe --headless --path <project> res://tests/scene_transition_source.tscn -- --async --platformer
```
