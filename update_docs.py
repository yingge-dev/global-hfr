import os

r = r'C:\Users\Colorful\Documents\deepseek-harness\default-workspace\global_hfr_repo'


def read(p):
    return open(p, encoding='utf-8').read()


def write(p, s):
    open(p, 'w', encoding='utf-8', newline='\n').write(s)


# PUSH.md
p = os.path.join(r, 'PUSH.md')
s = read(p).replace('YOUR_GITHUB_NAME', 'wy15623505520-droid')
old = """## 4. 发 Release（可选，但建议）

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
"""
new = """## 4. 发版（自动，推荐）

只需要改 `module/module.prop`：

```ini
version=v1.2.1
versionCode=10201
```

提交后打 tag，**tag 必须和 version 完全一致**：

```bash
git add .
git commit -m "release: v1.2.1"
git push
git tag v1.2.1
git push origin v1.2.1
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

- 旧版 `10200` → 新版 `10201`：会提示更新
- 只改代码、不升 `versionCode`：不会提示
- `v1.0.0` / `v1.1.0` 的旧包没有 `updateJson`：不会提示，需要手动装一次 v1.2.0 及以上
"""
assert old in s
s = s.replace(old, new)
write(p, s)

# root README
p = os.path.join(r, 'README.md')
s = read(p)
s = s.replace('├── update.json             # Magisk 更新配置（需替换仓库地址）',
              '├── update.json             # 自动生成，无需手改')
old2 = '或推送 `v*` tag，GitHub Actions 会自动打包并创建 Release。'
new2 = """## 发版（自动）

1. 修改 `module/module.prop` 的 `version` 与 `versionCode`；
2. 提交并推送 `main`；
3. 打一个和 `version` 完全一致的 tag：

```bash
git tag v1.2.1
git push origin v1.2.1
```

GitHub Actions 会自动打包、创建 Release、更新 `update.json` 和 `docs/assets/global-hfr.zip`，并触发 Pages 构建。之后已安装的旧版本会按 `versionCode` 检查更新。"""
assert old2 in s
s = s.replace(old2, new2)
write(p, s)

# module README version
p = os.path.join(r, 'module', 'README.md')
s = read(p).replace('版本：v1.2.0', '版本：v1.2.1')
marker = '### v1.2.0 更新'
if '### v1.2.1 更新' not in s and marker in s:
    s = s.replace(marker, """### v1.2.1 更新
- 发版流程自动化：推 `v*` tag 后自动打包、发 Release、更新 `update.json` 与 Pages 下载包

### v1.2.0 更新""", 1)
write(p, s)

print('docs updated')
