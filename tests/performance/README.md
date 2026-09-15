# UFrame 极限性能基准

本目录提供独立于普通正确性测试的可重复性能基准。它用于比较同一机器、同一 Godot 构建和同一负载档位下的变化，不使用固定毫秒数判定框架是否合格。

## 运行方式

在项目根目录执行：

```powershell
godot --headless --path . res://tests/performance/performance_runner.tscn -- --profile=quick
godot --headless --path . res://tests/performance/performance_runner.tscn -- --profile=standard
godot --headless --path . res://tests/performance/performance_runner.tscn -- --profile=stress
```

- `quick`：快速确认基准入口和正确性不变量，适合修改后的首次检查。
- `standard`：默认本地审查档位，适合提交前比较。
- `stress`：手动极限负载，可能持续较长时间，不应加入普通回归测试。

只运行部分场景：

```powershell
godot --headless --path . res://tests/performance/performance_runner.tscn -- --profile=standard --only=pool,event_bus
```

可选名称为 `event_bus`、`registry`、`inventory`、`stats`、`state_machine`、`input` 和 `pool`。

## 输出格式

每次运行输出三类单行 JSON：

```text
UFRAME_PERF_BEGIN {...}
UFRAME_PERF_RESULT {...}
UFRAME_PERF_SUMMARY {...}
```

全部正确性检查通过后额外输出 `UFRAME_PERF_OK` 并以退出码 `0` 结束。主要字段：

- `operations`：该基准可跨档位比较的最小工作单元；
- `elapsed_usec`：总耗时，单位为微秒；
- `usec_per_operation`：平均单次工作耗时；
- `operations_per_second`：当前运行环境中的吞吐；
- `capacity`、`subscribers`、`modifiers` 等：解释负载规模的附加字段。

## 覆盖内容

| 场景 | 极限路径 | 需要保持的正确性 |
|---|---|---|
| EventBus | 大量订阅、带订阅发布、空事件发布、失效监听清理 | 不漏回调、不重复回调 |
| Registry | 单一大内容桶注册、查询、键复制 | ID 与值保持一致 |
| Inventory | 1024 格不同物品逐项/批量填充、缓存查询、重复整理 | 不丢物、总数不变，批量与逐项的整理结果一致 |
| Stats | 同属性批量事务、受控规模逐项调用、缓存查询、失效重算、同帧到期 | 最终值、实际处理数量与修正列表正确 |
| StateMachine | 高频互斥切换和双帧转发 | enter/exit 成对且只更新当前状态 |
| Input | 大量同时缓冲动作的扫描、查询与过期 | 不提前过期、不残留 |
| Pool | 大容量预热、批量取还、满载溢出复用 | 不突破容量、不丢失生命周期 |

## 如何解释结果

1. 只比较相同 `profile`、Godot 版本、调试/发布构建和机器的结果。
2. 先观察 `usec_per_operation` 是否随着容量或订阅者数量异常上升，再检查对应实现的复杂度。
3. 一次结果可能受系统调度、编辑器和杀毒软件影响；重要结论至少重复三次并取中位数。
4. 微基准只隔离框架调度成本，不能替代真实玩法场景中的 Godot Profiler、渲染统计和物理监视器。
5. EventBus 明确面向低频跨系统通知；它的极限结果不能用来证明高频战斗应该改用全局发布。

普通功能回归仍使用 `res://tests/test_runner.tscn`，不要把 `stress` 档并入该入口。

## 2026-09-15 优化对比

同一台 Windows 机器、Godot 4.7.stable.official.5b4e0cb0f、headless、debug_build=true，前后各三次 standard 取中位数。以下为整项工作耗时：

| 工作 | 修改前 | 修改后 |
|---|---:|---:|
| 1024 种不可堆叠物品逐项填充 | 444.61 ms | 23.66 ms |
| 同样内容通过新 add_items 批量填充 | 无批量入口 | 2.76 ms |
| 1024 格连续整理 50 次的单次平均 | 5.69 ms | 1.11 ms |

重复整理基准包含已经有序的情况；改后跳过无变化写入和通知，但仍检查与排序。单次乱序整理、64 格实际 UI 与大量复杂节点物理开销应分别测量，不能把上述比例直接当作游戏帧率提升。

Stats 额外在同一进程交错运行修改前后版本 60 次，512 项批量添加中位数约 1.78 → 1.87 ms，移除约 0.73 → 0.69 ms；没有显著的全面速度提升。合并成员容器主要减少重复存储与维护，保留批量重算和缓存查询。EventBus 的有效订阅标记、StateMachine 的重入检查增加少量固定成本，用于保证同步回调正确性。
