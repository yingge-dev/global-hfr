# 上传到 GitHub（照着做）

## 0. 先替换占位符

把下面文件里的 `yingge-dev` 全部替换成你的 GitHub 用户名（例如 `yingge`）：

- `README.md`
- `update.json`
- `docs/index.html`
- `docs/app.js`
- `profile-README.md`

如果仓库名不叫 `global-hfr`，再把 `global-hfr` 一起替换成实际仓库名。

> `docs/app.js` 在 GitHub Pages 上会自动识别 `<用户名>.github.io/<仓库名>/`，通常不替换也能用；替换更稳。

---

## 1. 建仓库

在 GitHub 新建一个 **Public** 仓库，名字建议 `global-hfr`，不要勾选 README / .gitignore / License。

## 2. 本地初始化并推送

在 `global_hfr_repo` 目录打开终端：

```bash
git init
git add .
git commit -m "feat: 真·全局高刷 v1.2.0"
git branch -M main
git remote add origin https://github.com/yingge-dev/global-hfr.git
git push -u origin main
```

如果你装了 GitHub CLI，也可以：

```bash
gh repo create global-hfr --public --source=. --remote=origin --push
```

## 3. 开启 GitHub Pages

仓库 → **Settings** → **Pages**：

- Source：`Deploy from a branch`
- Branch：`main`
- Folder：`/docs`
- Save

等 1–2 分钟，访问：

```text
https://yingge-dev.github.io/global-hfr/
```

`docs/.nojekyll` 已放好，避免 Jekyll 处理静态资源。

## 4. 发版（自动，推荐）

只需要改 `module/module.prop`：

```ini
version=v1.2.2
versionCode=10202
```

提交后打 tag，**tag 必须和 version 完全一致**：

```bash
git add .
git commit -m "release: v1.2.2"
git push
git tag v1.2.2
git push origin v1.2.2
```

推送 tag 后，`.github/workflows/release.yml` 会自动：

1. 校验 tag 与 `module.prop` 的 `version` 是否一致；
2. 打包出 `global-hfr.zip`；
3. 创建 GitHub Release 并上传 zip；
4. 用 `module.prop` 里的版本号生成 `update.json`；
5. 把 `update.json` 和最新的 `docs/assets/global-hfr.zip` 提交回 `main`；
6. 触发一次 Pages 构建。

**不需要再手改 `update.json`**，也不用手动上传 zip。`updateJson` 已经在 `module.prop` 里配好。

## 5. 更新检查怎么生效

管理器会拿已安装模块的 `versionCode` 和 `update.json` 里的 `versionCode` 比较：

- 旧版 `10200` → 新版 `10202`：会提示更新
- 只改代码、不升 `versionCode`：不会提示
- `v1.0.0` / `v1.1.0` 的旧包没有 `updateJson`：不会提示，需要手动装一次 v1.2.0 及以上

## 6. 个人主页 README（可选）

1. 新建一个和用户名**完全同名**的仓库，例如 `yingge-dev/yingge-dev`；
2. 把本仓库的 `profile-README.md` 复制进去，重命名为 `README.md`；
3. 把里面的 `yingge-dev` 替换成你的用户名；
4. 提交后打开 `https://github.com/yingge-dev` 就能看到个人主页。

## 7. 发布前检查

- [ ] `README.md` 里的下载链接能点开
- [ ] `docs/assets/global-hfr.zip` 是最新模块包
- [ ] Pages 打开后图片、下载按钮正常
- [ ] Release 里的 zip 和 `docs/assets` 里的 zip 是同一个版本
- [ ] 144/165/185Hz 描述没有写成“全机型支持”
- [ ] 截图保留“界面示意”说明，避免被当成真机实拍

## 仓库结构

```text
.
├── module/                 # 模块源码
├── screenshots/            # 宣传图
├── docs/                   # GitHub Pages
│   ├── index.html
│   ├── style.css
│   ├── app.js
│   ├── .nojekyll
│   └── assets/
├── .github/workflows/
│   └── release.yml
├── update.json
├── profile-README.md
└── README.md
```
