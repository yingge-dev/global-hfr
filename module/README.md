# 真·全局高刷 · Global HFR

> 小米 / OPPO / 一加 全平台全局高刷与触控增强模块  
> 作者：**颖哥** ｜ 版本：v1.2.2 ｜ 适用：Android 11+（Magisk / KernelSU / APatch）

---

## 一、它到底做了什么

不是改个 `settings` 就自称全局。模块用三层机制锁定，并且**每次都会回读实际刷新率做核验**：

| 层级 | 手段 | 作用 |
| --- | --- | --- |
| ① 框架层 | `settings put system peak_refresh_rate / min_refresh_rate`，小米/澎湃额外写 `user_refresh_rate` | 告诉系统刷新率上下限，兼容所有 ROM |
| ② 底层锁 | `service call SurfaceFlinger 1035 i32 <modeId>` | 调用 AOSP `setActiveModeFromBackdoor`，把显示模式钉死在指定档位，并让 SurfaceFlinger 忽略后续应用/系统 UI 的帧率投票 |
| ③ 回退 | `cmd display set-user-preferred-display-mode <modeId>` | 部分 ROM 屏蔽 backdoor 时使用 DisplayManager 通道 |
| 核验 | 读取 `dumpsys display` 的实际 `refreshRate` 与 `mActiveModeId` | 未达到目标会重试，仍失败则在 UI 标记「待核验」 |

因此：

- **固定档位**：60 / 90 / 120 / 144 / 165 / 185Hz，只要机器（或超频 DTBO）里存在该显示模式，就能真锁死，包括视频 App、系统桌面、游戏。
- **动态刷新率**：60–120、60–144、60–165、30–120、10–120 等区间。先解除底层锁定，再把区间交给面板 LTPO 硬件调度：静态降频省电、滑动瞬间回峰值。
- **触控加速**：写入真实存在的内核 boost 节点，并提高触控 HAL 的调度优先级，缩短「触摸 → 渲染 → 上屏」链路。

> 说明：模块**不会**修改触控 IC 固件，也不谎称提升采样率。采样率由屏幕与厂商 HAL 决定；模块做的是让输入事件更快被调度、GPU 不拖后腿、画面更快上屏。

---

## 二、功能一览

### 刷新率
- 自动识别品牌 / 机型 / ROM / 平台（高通 / 联发科）
- 自动扫描 `SurfaceFlinger` / `dumpsys display` 全部显示模式（含超频 DTBO 档位，兼容 `Mode ID` 格式）
- 一键「全局最高」，或点选任意检测到的档位
- 动态区间自定义（下限 / 上限 + 常用预设）
- 深度锁帧开关（SurfaceFlinger 底层锁）
- 系统原生刷新率浮窗（肉眼核验）
- 息屏 / 亮屏 / 配置变更 / 刷新率漂移自动重锁
- 开机自动恢复上次配置

### 触控
- 高通 `msm_performance/touchboost`
- 内核 `cpu_boost/input_boost_enabled`
- `adreno_idler` 关闭（减少 GPU 降频等待）
- 联发科 `fpsgo` 强制开启
- 电竞模式额外：GPU governor → `performance`、`sched_boost=1`
- 触控 HAL / SurfaceFlinger 进程 `renice` 提权
- **所有节点写入前备份原值，关闭或卸载时逐项还原**

### WebUI
- KernelSU / APatch 模块页直接打开
- Magisk 用户安装 **KsuWebUI** 并授予 Root 后打开
- 实时显示当前刷新率、目标档位、核验方式、生效节点
- 玻璃拟态界面：自动 / 浅色 / 深色三档主题，适配状态栏与手势条安全区

---

## 三、安装

1. 下载 `真·全局高刷.zip`；
2. 在 **Magisk / KernelSU / APatch** 管理器里选择「从本地安装」；
3. 刷入后**重启手机**；
4. 首次开机会自动锁定面板最高刷新率；
5. 打开 WebUI 调整档位 / 动态区间 / 触控。

> 仅支持通过 Root 管理器安装（模块为纯脚本 + WebUI，不含 recovery 安装器）。  
> 不要与其他「高刷 / 刷新率 / LTPO / VRR / dfps」类模块同时启用，会互相抢显示策略。

### WebUI 入口
- **KernelSU / APatch**：模块卡片 → 打开 / WebUI
- **Magisk**：安装 [KsuWebUI](https://github.com/5ec1cff/KsuWebUIStandalone) 之类的 WebUI 宿主 App，授予 Root，选择「真·全局高刷」

---

## 四、使用建议

### 只想全局高刷
主页 →「全局最高」→ 回桌面滑动确认。  
状态卡显示「已锁定 / 已核验」即生效；显示「待核验」时打开「设置 → 帧率浮窗」肉眼确认，或查看日志。

### 想省电又顺滑
主页 →「动态刷新」→ 选 `60–120` / `60–144` / `60–165` → 应用。  
静态画面降到下限附近（把下限设为 10/30 时，部分 LTPO 机型还能更低），滑动/触控瞬间回上限，这是正常现象。

### 欧加系（OPPO / 一加 / realme）锁不住
设置 → 打开「OPPO 兼容模式」→ 重启。  
该开关会在 `post-fs-data` 阶段关闭欧加的动态帧率投票（`debug.oplus.display.dynamic_fps_switch` 等），让底层锁更稳。

### 小米 / HyperOS 锁不住
1. 确认「深度锁帧」开启；
2. 系统设置里关闭「智能刷新率 / 自适应刷新率」；
3. 设置 → 重新扫描档位；
4. 仍不行请看日志（设置 → 运行日志）。

---

## 五、关于 144 / 165 / 185Hz

模块**只能锁定设备真实存在的显示模式**：

- 面板原生 120Hz 的机器，不会凭空出现 144/165/185；
- 刷了超频 DTBO / 显示 KO 的机器，扫描到新档位后会自动出现并标注 `OC`；
- 未检测到的档位在 UI 中置灰，点了会提示，不会假装成功。

这也是「保证真实有效」的前提：不写不存在的模式，不伪造核验结果。

---

## 六、目录与数据

| 路径 | 内容 |
| --- | --- |
| `/data/adb/modules/global_hfr/` | 模块本体（脚本 + WebUI） |
| `/data/adb/global_hfr/config.conf` | 用户配置（卸载时删除） |
| `/data/adb/global_hfr/modes.tsv` | 扫描到的显示档位 |
| `/data/adb/global_hfr/state.conf` | 最近一次应用状态 |
| `/data/adb/global_hfr/touch.backup` | 触控节点原值备份 |
| `/data/adb/global_hfr/run.log` | 运行日志（自动截断） |

命令行（Termux / adb shell，需 root）：

```sh
sh /data/adb/modules/global_hfr/hfr.sh status
sh /data/adb/modules/global_hfr/hfr.sh preset max
sh /data/adb/modules/global_hfr/hfr.sh preset dynamic 60 120
sh /data/adb/modules/global_hfr/hfr.sh touch on
sh /data/adb/modules/global_hfr/hfr.sh log 80
sh /data/adb/modules/global_hfr/hfr.sh restore
```

---

## 七、常见问题

**Q：显示「已锁定」但个别 App 还是 60Hz？**  
先开「帧率浮窗」看系统实际输出。若浮窗是 120 而 App 内画面仍卡，是 App 自身渲染限制（如视频 24/30fps），不是刷新率没锁。深层锁帧会压住 App 的帧率投票，但压不住内容本身只有 30 帧。

**Q：重启后恢复默认了？**  
确认「开机自动应用」与「后台守护」都开启；若使用 Magisk，确认模块未处于「禁用」状态。

**Q：把下限设为 10Hz 后，静止时真的掉到 10Hz，正常吗？**  
正常。LTPO 面板在静态画面会进入低刷新率省电；下限是允许的最低值，不是全程钉死。若希望静止也保持 60，把下限设为 60 即可。

**Q：耗电变快？**  
固定 165/185Hz 全程锁死必然更耗电。日常建议动态区间或 120Hz；电竞触控也会提高 GPU/调度功耗。

**Q：闪屏、黑屏、花屏？**  
立即「设置 → 恢复系统默认」，重启；仍异常则在管理器里卸载模块并重启。超频档位不稳定请换低一档。

**Q：和 dfps / Astra / 其他高刷模块能一起用吗？**  
不要。它们会同时改 `peak_refresh_rate` 与 SurfaceFlinger 策略，互相覆盖，表现为跳档、锁不住、耗电异常。

---

## 八、卸载

- 管理器内卸载 → 重启；
- 卸载脚本会停守护、还原刷新率设置、逐项还原触控节点、关闭浮窗与底层锁；
- 配置与日志一并删除。

---

## 九、免责声明

本模块通过 Root 修改系统显示与调度策略，属于**高风险操作**。请确保具备救砖能力后再使用。  
不同 ROM / 内核 / 超频 DTBO 的行为差异很大，作者不对因使用本模块造成的设备异常、数据丢失或硬件损坏负责。  
刷入即表示你已理解并接受上述风险。

---

## 十、致谢与参考

- AOSP `SurfaceFlinger`：`setActiveModeFromBackdoor` / `setDesiredDisplayModeSpecsInternal`（transaction 1035 / 1036）
- [yc9559/dfps](https://github.com/yc9559/dfps)：PEAK_REFRESH_RATE 与 SurfaceFlinger backdoor 两种低层路径的公开实践
- [MuYuanXing/Astra_MaxRefresh_Pro](https://github.com/MuYuanXing/Astra_MaxRefresh_Pro)：欧加系档位扫描与切换思路
- KernelSU WebUI API：`ksu.exec` / `ksu.toast`

---

**真·全局高刷 · 颖哥**  
如果这个模块让你觉得手机顺了一点，那就够了。
