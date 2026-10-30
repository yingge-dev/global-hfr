# 上传到 GitHub（照着做）

## 0. 先替换占位符

把下面文件里的 `YOUR_GITHUB_NAME` 全部替换成你的 GitHub 用户名（例如 `yingge`）：

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
git remote add origin https://github.com/YOUR_GITHUB_NAME/global-hfr.git
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
https://YOUR_GITHUB_NAME.github.io/global-hfr/
```

`docs/.nojekyll` 已放好，避免 Jekyll 处理静态资源。

## 4. 发 Release（可选，但建议）

推送 tag 会自动触发 `.github/workflows/release.yml`，打包并上传 `global-hfr.zip`：

```bash
git tag v1.2.0
git push origin v1.2.0
```

也可以手动：Releases → Draft a new release → 选 tag `v1.2.0` → 上传 `docs/assets/global-hfr.zip`（可改名为 `global-hfr.zip`）。

Release 发好后，`update.json` 里的地址就能用了。

## 5. 让 Magisk 支持自动更新（可选）

在 `module/module.prop` 末尾加一行（把用户名换成你的）：

```ini
updateJson=https://raw.githubusercontent.com/YOUR_GITHUB_NAME/global-hfr/main/update.json
```

然后重新打包 zip、重新发 Release。不加也不影响模块使用，只是管理器不会提示更新。

## 6. 个人主页 README（可选）

1. 新建一个和用户名**完全同名**的仓库，例如 `YOUR_GITHUB_NAME/YOUR_GITHUB_NAME`；
2. 把本仓库的 `profile-README.md` 复制进去，重命名为 `README.md`；
3. 把里面的 `YOUR_GITHUB_NAME` 替换成你的用户名；
4. 提交后打开 `https://github.com/YOUR_GITHUB_NAME` 就能看到个人主页。

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
