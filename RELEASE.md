# 发版流程

以后优化模块，默认按这个流程走：**改完代码 → 测完 → 发新版到 GitHub**，不要只停在本地。

## 1. 改模块

- `module/hfr.sh`、`module/webroot/`、`module/customize.sh` 等
- 有功能变化时更新 `CHANGELOG.md`
- WebUI 有改动时同步更新 `screenshots/` 和 `docs/assets/` 里的截图
- 只改代码也要升版本号，否则管理器不会提示更新

## 2. 本地验证

```bash
cd module
bash -n hfr.sh
bash -n customize.sh
```

至少确认：

- 模块能正常解压/安装
- WebUI 能打开，档位/主题/恢复按钮不报错
- 卸载逻辑没被破坏
- zip 结构里 `module.prop` 在最外层

## 3. 一键发版

在仓库根目录执行：

```powershell
.\release.ps1 v1.2.3
```

脚本会自动：

1. 校验 tag 格式；
2. 把 `module.prop` 的 `version` 改成 `v1.2.3`；
3. 把 `versionCode` 自动 +1；
4. commit + push `main`；
5. 打 tag 并 push。

随后 `.github/workflows/release.yml` 自动：

- 打包 `global-hfr.zip`
- 创建 GitHub Release
- 生成新的 `update.json`
- 更新 `docs/assets/global-hfr.zip`
- 触发 Pages 构建

## 4. 手动发版（等价）

```powershell
# 1. 改 module/module.prop
version=v1.2.3
versionCode=10203

# 2. 提交
git add .
git commit -m "release: v1.2.3"
git push

# 3. 打 tag（必须和 version 一致）
git tag v1.2.3
git push origin v1.2.3
```

## 5. 发完检查

- Release 里有 `global-hfr.zip`
- `update.json` 的 `versionCode` 已增加
- 主页下载按钮正常
- 旧版本管理器能看到更新提示
- 桌面上的 `真·全局高刷.zip` 换成新包（可选）

> 注意：`versionCode` 只能升不能降；tag 必须和 `module.prop` 的 `version` 完全一致，否则 Actions 会直接失败。
