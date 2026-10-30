# Changelog

## v1.2.1

- 发布流程自动化：推送 * tag 后，GitHub Actions 自动打包、创建 Release、更新 update.json 与 Pages 下载包

## v1.2.0

- WebUI 改为玻璃拟态：半透明材质、分组列表、开关与分段控件、自动 / 浅色 / 深色三档主题
- 模块名统一为 **真·全局高刷**（不再带版本号），压缩包同名
- 固定档位额外写入小米 / 澎湃的 `user_refresh_rate`，动态档位自动还原
- 新增 `Mode ID: N, Resolution: WxH, Refresh Rate: F` 格式的档位解析，兼容更多 ROM
- 模块描述与界面文案统一去除品牌化字样

## v1.1.0

- 增加 `user_refresh_rate` 写入与还原
- 增加 `Mode ID` 格式的显示模式解析

## v1.0.0

- 首个版本：固定档位、动态区间、SurfaceFlinger 1035 锁定、回读核验
- 触控加速与节点备份还原
- KernelSU / APatch WebUI，Magisk + KsuWebUI
