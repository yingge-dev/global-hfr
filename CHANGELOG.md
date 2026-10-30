# Changelog

## v1.3.0

- 新增全局触控采样率：240 / 360 / 480Hz（Xiaomi thp 节点，无需游戏助手）
- 档位切换改为单进程 `switch`，WebUI 点击即时反馈
- 缩短 SurfaceFlinger 核验等待，减少切换时的停顿
- 触控页新增采样率控制与节点检测

## v1.2.2

- 发布流程自动化：推送 * tag 后，GitHub Actions 自动打包、创建 Release、更新 update.json 与 Pages 下载包
