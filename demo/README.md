# UcatFrame 示例

本目录包含框架的使用示例。

---

## 1. 状态机示例

场景：`demo/state_machine_demo.tscn`

场景树结构：
```
StateMachineDemo (Node2D)          ← 挂载 state_machine_demo.gd
  └── Player (CharacterBody2D)
        ├── Sprite2D
        ├── CollisionShape2D
        └── StateMachine (挂载 StateMachine.gd)
              ├── IdleState.gd
              └── RunState.gd
```

**IdleState.gd**
```gdscript
extends State

func update(_delta: float) -> void:
    if Input.is_action_pressed("ui_right") or Input.is_action_pressed("ui_left"):
        transition_to("RunState")

func enter(_prev: String, _data) -> void:
    print("进入 Idle")
```

**RunState.gd**
```gdscript
extends State

func update(_delta: float) -> void:
    if not (Input.is_action_pressed("ui_right") or Input.is_action_pressed("ui_left")):
        transition_to("IdleState")

func enter(_prev: String, _data) -> void:
    print("进入 Run")
```

---

## 2. 事件总线示例

**发送事件：**
```gdscript
EventBus.send("PlayerHurt", {"damage": 20, "source": self})
```

**监听事件（自动注销）：**
```gdscript
func _ready():
    EventBus.subscribe("PlayerHurt", _on_hurt, self)

func _on_hurt(data: Dictionary) -> void:
    print("受到 %d 点伤害" % data.damage)
```

---

## 3. Registry 注册内容示例

**定义武器数据（weapon_fire_sword.tres）：**
```
# 在 Godot 编辑器中：
# 1. 新建 Resource，类型选 DataComponent
# 2. 保存为 weapon_fire_sword.tres
# 3. 填写 id="weapon:fire_sword", display_name="火焰剑", tier=1
```

**注册和使用：**
```gdscript
# 手动注册
var data = load("res://data/weapons/weapon_fire_sword.tres")
Registry.register("weapon", data.id, data)

# 或批量扫描目录
Registry.register_from_directory("weapon", "res://data/weapons/", "weapon")

# 获取
var sword = Registry.get_value("weapon", "weapon:fire_sword")
print(sword.display_name)  # "火焰剑"
```

---

## 4. GameState 状态管理示例

```gdscript
func _ready():
    GameState.connect("score_changed", _on_score_changed)

func _on_score_changed(old_val, new_val) -> void:
    print("分数变化: %d → %d" % [old_val, new_val])
    score_label.text = str(new_val)

# 修改状态（触发 signal）
GameState.score = 100
```
