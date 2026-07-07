# UcatFrameWork

通用 Godot 4 游戏开发框架。

设计目标：** 插拔内容，数据驱动，保持轻量。**

---

## 核心理念

| 理念 | 来源 | 实现 |
|---|---|---|
| 内容=数据文件，不碰核心代码 | Minecraft Mod | `Registry` + `BaseData` Resource |
| 逻辑集中，节点只管表现 | Brotato | `services/` 层 |
| 模块间不直接依赖 | Minecraft Forge | `EventBus` 事件通信 |
| 行为可组合，不写巨型脚本 | Brotato | `components/` 组件系统 |
| 状态切换开箱即用 | 通用 | `StateMachine` 组件 |

---

## 快速开始

### 1. 安装

将 `UcatFrameWork/` 文件夹复制到你的 Godot 项目 `addons/` 目录下。

### 2. 启用插件

打开 **项目设置 → 插件**，勾选启用 `UcatFrame`。

插件启用时会**自动注册所有 Autoload**，无需手动添加：

| 单例名称 | 脚本路径 | 说明 |
|---|---|---|
| `UcatFrame` | `core/UcatFrame.gd` | 框架总入口 |
| `EventBus` | `core/EventBus.gd` | 全局事件总线 |
| `Registry` | `core/Registry.gd` | 内容注册总线 |
| `SaveService` | `services/SaveService.gd` | 存档/读档 |
| `AudioService` | `services/AudioService.gd` | 音效统一管理 |
| `CameraService` | `services/CameraService.gd` | 相机震动/慢动作 |
| `TransitionService` | `services/TransitionService.gd` | 场景切换过渡 |

> `PoolService.gd` 是纯静态类，不需要 Autoload，直接 `PoolService.register()` 调用即可。
>
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

func update(delta):
	if Input.is_action_pressed("move_right"):
		transition_to("RunState")

func enter(_prev, _data):
	print("进入待机")
```

---

## 模块说明

### `core/UcatFrame.gd`
框架总入口，统一管理初始化流程。项目可继承此类扩展。

### `event_bus/EventBus.gd`
全局事件总线。模块间通过事件名通信，不直接引用。

```gdscript
# 发送
EventBus.send("PlayerDamaged", {"damage": 10})

# 订阅（节点销毁时自动注销）
EventBus.subscribe("PlayerDamaged", _on_damaged, self)
```

### `registry/Registry.gd`
内容注册总线。所有武器/敌人/物品必须注册，通过 ID 引用。

```gdscript
# 注册
Registry.register("weapon", "mygame:fire_sword", sword_data)

# 获取
var sword = Registry.get_value("weapon", "mygame:fire_sword")

# 批量扫描目录
Registry.register_from_directory("weapon", "res://data/weapons/", "mygame")
```

### `services/` — 工具服务层

纯逻辑模块，不挂节点，提供全局方法。

| Service | 说明 | 是否需要 Autoload |
|---|---|---|
| `SaveService.gd` | 存档/读档，序列化 Resource | ✅ 需要 |
| `AudioService.gd` | 统一管理音效，对象池限制并发 | ✅ 需要 |
| `CameraService.gd` | 屏幕震动（Perlin Noise）、慢动作 | ✅ 需要 |
| `TransitionService.gd` | 场景切换淡入淡出（CanvasLayer） | ✅ 需要 |
| `PoolService.gd` | 对象池，管理子弹/粒子复用 | ❌ 静态类，直接调用 |

```gdscript
SaveService.save(RunData_instance, "slot_1")
AudioService.play_sfx(load("res://sfx/hit.wav"))
CameraService.add_trauma(0.6)
await TransitionService.change_scene("res://levels/level2.tscn")
PoolService.register("bullet", bullet_scene, 20)
# 也可以指定父节点：PoolService.register("bullet", bullet_scene, 20, self)
var b = PoolService.get_instance("bullet")
```

### `components/` — 可复用节点组件

挂到场景树上即可使用的通用组件，避免写巨型脚本。

| 组件 | 说明 |
|---|---|
| `StateMachine.gd` + `State.gd` | 状态机节点，子节点自动识别为状态 |
| `StateMachineHelper.gd` | 纯代码版状态机，适合简单场景 |
| `BehaviorBase.gd` | 行为委托基类，把逻辑拆成子节点 |
| `HealthComponent.gd` | 生命值组件，信号驱动 UI，支持无敌时间 |
| `HitboxComponent.gd` | 攻击碰撞框，碰到 Hurtbox 造成伤害 |
| `HurtboxComponent.gd` | 受击碰撞框，被 Hitbox 碰到时通知 HealthComponent |
| `InventoryComponent.gd` | 背包组件，支持堆叠/数量管理/重量限制 |
| `PoolComponent.gd` | 对象池组件，挂到节点上，销毁时自动清理 |

```gdscript
# 生命值组件使用示例
var hp = $HealthComponent
hp.take_damage(20, self)
hp.hp_changed.connect(_update_hp_bar)
hp.died.connect(_on_death)

# 背包组件使用示例
$InventoryComponent.add_item("mygame:fire_sword", 1)
if $InventoryComponent.has_item("mygame:key", 3):
	open_door()
```

### `resources/BaseData.gd`
所有内容 Resource 的基类。子类加字段即可定义新内容类型。
项目里继承它创建 `WeaponData.gd`、`EnemyData.gd` 等。

### `utils/` — 纯工具函数库

静态类，无状态，直接 `XXXUtil.xxx()` 调用，不需要挂载或 Autoload。

| 工具类 | 主要功能 |
|---|---|
| `MathUtil.gd` | 随机范围、角度/向量互转、插值、洗牌、加权随机 |
| `TimeUtil.gd` | 秒数格式化（MM:SS）、延时/定时器简化 |
| `NodeUtil.gd` | 安全节点查找、递归查找子节点、安全移除 |
| `RandomUtil.gd` | 随机布尔/向量/颜色/字符串、概率判定 |
| `ColorUtil.gd` | Hex 与 Color 互转、颜色混合、色板 |

```gdscript
var dir = MathUtil.angle_to_vector2(45)
var t = TimeUtil.format_seconds(125)   # "02:05"
var ui = NodeUtil.get_node_safe(self, "UI/HealthBar")
if RandomUtil.chance(0.3): spawn_bonus()
modulate = ColorUtil.hex_to_color("#FF5722")
```

---

## 扩展框架

推荐方式：创建你的游戏架构脚本，继承 `UcatFrame`：

```gdscript
# my_game.gd
extends UcatFrame

func _init_framework():
	# 注册内容
	Registry.register_from_directory("weapon", "res://data/weapons/", "mygame")
```

然后将 `my_game.gd` 设为 Autoload（替换或叠加 `UcatFrame`）。

---

## 目录结构

```
UcatFrameWork/
├── core/
│   └── UcatFrame.gd            # 框架总入口
├── event_bus/
│   └── EventBus.gd              # 事件总线
├── registry/
│   └── Registry.gd              # 内容注册总线
├── services/                      # 全局服务层（需 Autoload）
│   ├── SaveService.gd
│   ├── AudioService.gd
│   ├── CameraService.gd
│   ├── TransitionService.gd
│   └── PoolService.gd            # 静态类
├── state_machine/                  # 状态机组件
│   ├── State.gd
│   ├── StateMachine.gd
│   └── StateMachineHelper.gd
├── behaviors/                     # 行为委托组件
│   └── BehaviorBase.gd
├── components/                    # 其他可复用节点组件
│   ├── HealthComponent.gd
│   ├── HitboxComponent.gd
│   ├── HurtboxComponent.gd
│   ├── InventoryComponent.gd
│   └── PoolComponent.gd          # 对象池组件
├── resources/
│   └── BaseData.gd              # 数据 Resource 基类
├── utils/                         # 纯工具函数库（静态类）
│   ├── MathUtil.gd
│   ├── TimeUtil.gd
│   ├── NodeUtil.gd
│   ├── RandomUtil.gd
│   └── ColorUtil.gd
└── README.md
```

### 各层职责

| 层 | 说明 | 是否有状态 |
|---|------|----------|
| `core/` | 框架初始化入口 | 有（Autoload） |
| `services/` | 提供特定功能方法，不挂节点 | 部分有 |
| `components/` | 其他通用节点组件（战斗/背包等） | 有 |
| `resources/` | 数据模板基类 | 有（字段数据） |
| `utils/` | 纯工具函数，静态调用 | 无 |

---

---

## 版本

`0.1.0` — 构建基础架构
