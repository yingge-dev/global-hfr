# Changelog

## v2.1.0

兼容性重构：不再只针对一台 Xiaomi 设备写死，改成“能力检测 + 多级回退”。

- 新增设备能力自检：SurfaceFlinger 底层锁、DisplayManager `cmd display`、厂商刷新率键、系统原生上限；WebUI 设置页可随时查看。
- 固定档三级回退：Settings → DisplayManager → SurfaceFlinger；每一步回读实际刷新率，全部失败标「兼容模式」，不谎称成功。
- 新增通用自适应：没有 1035 底层锁的机型，改用 `min_refresh_rate` / `peak_refresh_rate` 切换，触控升上限、静止回下限。
- 厂商刷新率键自动发现：HyperOS 的 `miui_refresh_rate`，OPPO / 一加 / realme 的厂商键，存在才写入，写前备份。
- 非小米机型不再误用 SurfaceFlinger 1035；底层锁只在能力检测通过时启用。
- 按系统原生上限给建议：原生动态跑不满面板时自动推荐自适应。
- WebUI 新增「兼容性自检」，显示本机可用接口、系统上限、推荐动态与实际刷新率。
- 项目主页新增版本发布横幅与更新日志。

`v2.0.0` 的动态修复继续保留：HyperOS secure 刷新率、底层锁残留、原生 / 自适应双引擎、WebUI 状态缓存提速。

## v2.0.0

动态刷新率重做，修复「静态画面不降 60」与「切回动态仍被锁在高刷」两个根因。

- 修复 HyperOS 动态刷新率：补充写入 `miui_refresh_rate`，`peak` / `min` 与系统 secure 刷新率同时生效；静止画面可以正常回到下限。
- 新增双动态引擎：
  - `原生`：交给 DisplayManager / LTPO 按画面内容调度，最省电；系统有 120Hz 策略上限时最高 120Hz。
  - `自适应`：模块根据用户活动切换 SurfaceFlinger 模式，触控瞬间到上限、静止 3 秒回下限；可绕过系统 120Hz 上限跑满 60–165Hz。
- 修复固定档位 → 动态的底层锁残留：自动识别并切到自适应（立即生效）；手动切原生时明确提示需要重启，不再假装成功。
- 新增动态预设：60–120 / 60–144 / 60–165 / 120–165 / 90–165 / 30–120，按面板实际档位生成。
- 新增「静止降频时间」与「动态实现」选择，按机型自动给出推荐。
- 机型识别升级：读取面板档位、系统原生上限 `mLockedMaxRefreshRate`、厂商与 ROM；非小米机型使用 `cmd display` / Settings 通用回退。
- WebUI 延迟优化：状态接口改为缓存文件 + shell 内置解析，轮询不再每次跑 `dumpsys`；实测 `status` 从 1.5s 降到 0.15s，档位切换 0.2–0.3s。
- WebUI 新增 GitHub 更新检查、更新日志、重启提示；旧版可通过模块管理器的 `updateJson` 收到更新角标。
- 统一版本号与更新流程：GitHub Actions 在推送 `v*` tag 后自动打包、发布 Release、更新 `update.json` 与 Pages 下载包。

已知限制：

- 部分 HyperOS 把 144 / 165Hz 作为底层增强档，系统原生动态上限为 120Hz；需要 165Hz 动态请用「自适应」或「全局最高」。
- `自适应` 每秒读取一次电源状态，耗电略高于原生动态；日常 60–120Hz 建议直接用原生。

## v1.3.0

- 档位切换改为单进程 `switch`，WebUI 点击即时反馈
- 缩短 SurfaceFlinger 核验等待，减少切换时的停顿

## v1.2.2

- 发布流程自动化：推送 `v*` tag 后，GitHub Actions 自动打包、创建 Release、更新 update.json 与 Pages 下载包
