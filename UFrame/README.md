# UFrame

通用 Godot 4 游戏开发框架。

设计目标：**插拔内容，数据驱动，保持轻量。**

---

## 核心理念

| 理念 | 来源 | 实现 |
|---|---|---|
| 内容=数据文件，不碰核心代码 | Minecraft Mod | `Registry` + `ResourceData` Resource |
| 逻辑集中，节点只管表现 | Brotato | `services/` 层 |
| 模块间不直接依赖 | Minecraft Forge | `EventBus` 事件通信 |
| 行为可组合，不写巨型脚本 | Brotato | `components/` 组件系统 |
| 状态切换开箱即用 | 通用 | `StateMachine` 组件 |

---

## 快速开始

### 1. 安装

将 `UFrame/` 文件夹复制到你的 Godot 项目 `addons/` 目录下。

### 2. 启用插件

打开 **项目设置 → 插件**，勾选启用 `UcatFrame`。

插件启用时会**自动注册所有 Autoload**，无需手动添加：

| 单例名称 | 脚本路径 | 说明 |
|---|---|---|
| `UcatFrame` | `core/UcatFrame.gd` | 框架总入口，发出 `framework_ready` 信号 |
| `EventBus` | `core/EventBus.gd` | 全局事件总线 |
| `Registry` | `core/Registry.gd` | 内容注册总线 |
| `SaveService` | `services/SaveService.gd` | 存档/读档 |
| `AudioService` | `services/AudioService.gd` | 音效统一管理 |
| `CameraService` | `services/CameraService.gd` | 相机震动/慢动作 |
| `TransitionService` | `services/TransitionService.gd` | 场景切换过渡 |
| `SceneService` | `services/SceneService.gd` | 场景加载/堆栈管理 |
| `InputService` | `services/InputService.gd` | 输入缓冲/锁定 |

> 禁用插件时会自动移除所有 Autoload，不会残留。

### 3. 第一个状态机

场景树：
```
Player (CharacterBody2D)
  └── StateMachine (挂载 StateMachine.gd)
        ├── IdleState.gd   (继承 State)
        └── RunState.gd    (继承 State)
```

`IdleState.gd` 示例：
```gdscript
extends State

func on_update(delta):
    if Input.is_action_pressed("move_right"):
        state_machine.change_state("RunState")

func on_enter(_data):
    print("进入待机")
```

---

## 模块说明

### `core/` — 框架核心

#### `UcatFrame.gd`
框架总入口，统一管理初始化流程。就绪时发出 `framework_ready` 信号。

```gdscript
# 等待框架就绪
UcatFrame.framework_ready.connect(_on_framework_ready)

# 项目可继承 UcatFrame 扩展初始化
# 创建 my_game.gd → extends UcatFrame → 重写 _init_framework()
```

#### `EventBus.gd`
全局事件总线。模块间通过事件名通信，不直接引用。节点销毁时自动注销。

```gdscript
# 发送
EventBus.send("PlayerDamaged", {"damage": 10})

# 订阅（绑定节点生命周期，自动注销）
EventBus.subscribe("PlayerDamaged", _on_damaged, false, self)

# 一次性订阅
EventBus.subscribe("GameStart", _on_start, true, self)
```

#### `Registry.gd`
内容注册总线。所有武器/敌人/物品必须注册，通过 ID 引用。支持命名空间前缀 `"modname:item_name"`。

```gdscript
# 注册
Registry.register("weapon", "mygame:fire_sword", sword_data)

# 获取
var sword = Registry.get_value("weapon", "mygame:fire_sword")

# 批量扫描目录
Registry.register_from_directory("weapon", "res://data/weapons/", "mygame")

# 遍历
for id in Registry.list_ids("weapon"):
    print(id)

# 注销
Registry.unregister("weapon", "mygame:fire_sword")
```

---

### `services/` — 服务层（全部为 Autoload）

| Service | 说明 |
|---|---|
| `SaveService` | 存档/读档，序列化 Resource 到 `.tres` 文件 |
| `AudioService` | 统一音效管理，内置 SFX 对象池限制并发 |
| `CameraService` | 屏幕震动（trauma/Perlin Noise）、一次性 shake/punch |
| `TransitionService` | 场景切换淡入淡出、flash 闪光过渡 |
| `SceneService` | 场景加载/切换/堆栈、附加场景管理 |
| `InputService` | 输入缓冲、输入锁定、动作状态查询 |

```gdscript
# 存档
SaveService.save(run_data, "slot_1")

# 相机震动
CameraService.add_trauma(0.6)

# 场景切换
await TransitionService.fade_out()
SceneService.change_scene("res://levels/level2.tscn")

# 输入缓冲
InputService.buffer_action("attack", 0.15)
if InputService.is_action_buffered("attack"):
    perform_attack()
```

---

### `components/` — 可复用节点组件

| 组件 | 说明 |
|---|---|
| `StateMachine` + `State` | 场景树状态机，子节点自动识别为状态 |
| `StateMachineHelper` | 纯代码版状态机，不依赖场景树 |
| `BehaviorBase` | 行为委托基类，拆分逻辑为独立子节点 |
| `HealthComponent` | 生命值管理，统管无敌计时器 |
| `HitboxComponent` | 攻击判定框 (Area2D)，命中后通过 EventBus 通知 |
| `HurtboxComponent` | 受击判定框 (Area2D)，转发伤害给 HealthComponent |
| `InventoryComponent` | 背包组件，支持堆叠/容量管理 |
| `PoolComponent` | 场景对象池，挂到节点上自动创建/回收实例 |
| `TeamComponent` | 阵营/队伍，判断敌我关系 |

```gdscript
# 生命值组件（无敌由 HealthComponent 集中管理）
$HealthComponent.take_damage(20, attacker)
$HealthComponent.is_invincible()  # 查询无敌状态

# 阵营判断
var my_team = TeamComponent.of(self)
var their_team = TeamComponent.of(target)
if my_team.is_hostile(their_team):
    attack()

# 对象池
var bullet = $BulletPool.get_instance()
$BulletPool.release(bullet)
```

---

### `resources/` — 数据 Resource 类型

| Resource | 说明 |
|---|---|
| `ResourceData` | 所有内容 Resource 的基类（id/名称/图标/标签/品阶） |
| `RunData` | 存档数据基类（版本号/时长/时间戳/自定义字段） |
| `LootTable` | 掉落表，支持加权随机 + 保底机制 |
| `StatModifier` | 属性修正（加法/乘法/百分比/覆盖），支持优先级和时间限制 |

```gdscript
# 定义武器数据：新建 Resource → 类型选 ResourceData → 填写字段
# 定义掉落表：新建 Resource → 类型选 LootTable → 编辑 entries
var loot = loot_table.roll()  # {"item_id": "mygame:potion", "count": 2}
```

---

### `utils/` — 纯工具函数库（静态类，无需 Autoload）

| 工具类 | 主要功能 |
|---|---|
| `MathUtil` | 角度/向量互转、插值、浮点比较、值域映射 |
| `RandomUtil` | 随机数/数组/加权/洗牌/向量/颜色/字符串（全部随机功能集中于此） |
| `TimeUtil` | 秒数格式化、延时/定时器简化 |
| `NodeUtil` | 安全节点查找、递归搜索、安全移除 |
| `ColorUtil` | Hex 互转、颜色混合、亮度调整、Material Design 色板 |
| `Easing` | 30+ 缓动函数枚举 + 静态计算器 |

```gdscript
var dir = MathUtil.angle_to_vector2(45)
var t = TimeUtil.format_seconds(125)        # "02:05"
var ui = NodeUtil.get_node_safe(self, "UI/HealthBar")
if RandomUtil.chance(0.3): spawn_bonus()
modulate = ColorUtil.hex_to_color("#FF5722")
var eased = Easing.ease(Easing.Type.OUT_ELASTIC, t)
```

---

## 初始化流程

```
├─ UcatFrame._ready()
│   ├─ _init_framework()  （子类可重写）
│   └─ framework_ready 信号发出
│
├─ EventBus 就绪（订阅/发送可用）
├─ Registry 就绪（注册/查询可用）
├─ 各 Service 就绪
│
└─ 游戏逻辑层：
    ├─ Registry.register_from_directory()   注册内容
    ├─ EventBus.subscribe()                  连接全局事件
    └─ 正常游戏循环
```

项目可继承 `UcatFrame` 扩展初始化：

```gdscript
# my_game.gd
extends UcatFrame

func _init_framework():
    Registry.register_from_directory("weapon", "res://data/weapons/", "mygame")
    Registry.register_from_directory("enemy", "res://data/enemies/", "mygame")
```

---

## 目录结构

```
UFrame/
├── core/
│   ├── UcatFrame.gd              # 框架总入口
│   ├── EventBus.gd               # 事件总线
│   └── Registry.gd               # 内容注册总线
├── services/                       # 全局服务层（Autoload）
│   ├── SaveService.gd
│   ├── AudioService.gd
│   ├── CameraService.gd
│   ├── TransitionService.gd
│   ├── SceneService.gd
│   └── InputService.gd
├── components/
│   ├── state_machine/              # 状态机
│   │   ├── State.gd
│   │   ├── StateMachine.gd
│   │   └── StateMachineHelper.gd
│   ├── behaviors/
│   │   └── BehaviorBase.gd
│   ├── HealthComponent.gd
│   ├── HitboxComponent.gd
│   ├── HurtboxComponent.gd
│   ├── InventoryComponent.gd
│   ├── PoolComponent.gd
│   └── TeamComponent.gd
├── resources/                      # 数据 Resource 类型
│   ├── ResourceData.gd
│   ├── RunData.gd
│   ├── LootTable.gd
│   └── StatModifier.gd
├── utils/                          # 纯工具函数库（静态类）
│   ├── MathUtil.gd
│   ├── RandomUtil.gd
│   ├── TimeUtil.gd
│   ├── NodeUtil.gd
│   ├── ColorUtil.gd
│   └── Easing.gd
├── plugin.cfg
├── UcatFramePlugin.gd
└── README.md
```

### 各层职责

| 层 | 说明 | 是否有状态 |
|---|------|----------|
| `core/` | 框架入口、事件、注册 | 有（Autoload） |
| `services/` | 全局功能服务 | 部分有 |
| `components/` | 实体组件（挂节点） | 有（场景节点） |
| `resources/` | 数据模板基类 | 有（Resource 字段） |
| `utils/` | 纯函数，静态调用 | 无 |

---

## 版本

`0.2.0` — 事件总线 + 注册系统 + 状态机 + 组件 + 服务层 + 补间引擎
