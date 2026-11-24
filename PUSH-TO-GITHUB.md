# GitHub 发布与上架操作清单

仓库：`zz19940402/dsh-news-skill`
本地目录：`D:\BaiduNetdiskDownload\deepseek-windows64\skill\news`
当前 commit：`eee2186`（已初始化，未设 remote，未 push）

---

## 第一步：在 GitHub 网页建空仓库

1. 打开 https://github.com/new
2. Repository name: `dsh-news-skill`
3. Description 可填：`DSH news skill with four categories`
4. **选 Public**（市场评审要求公开仓库）
5. **不要**勾选 "Add a README" / ".gitignore" / license —— 本地已有，避免冲突
6. 点 **Create repository**

---

## 第二步：本地 push

建仓后，在本地目录执行（PowerShell）：

```powershell
cd "D:\BaiduNetdiskDownload\deepseek-windows64\skill\news"
git remote add origin https://github.com/zz19940402/dsh-news-skill.git
git push -u origin master
```

如果 GitHub 提示默认分支是 `main`，用：

```powershell
git branch -M main
git push -u origin main
```

push 完打开 `https://github.com/zz19940402/dsh-news-skill` 确认文件都在。

---

## 第三步：给仓库加 `dsh-plugin` topic

市场收录要求之一。在仓库页面：

- 右侧 **About** → 齿轮图标 → Topics 输入框填 `dsh-plugin` → 保存

---

## 第四步：等满 1 天

市场 CI 自动检查**仓库创建满 24 小时**。刚建就提 PR 会被自动拒。
利用这段时间可以：确认 README 显示正常、脚本能跑、图标显示正常。

---

## 第五步：向 awesome-dsh-plugin 提 PR

1. Fork https://github.com/awesome-dsh-plugin/awesome-dsh-plugin 到你账号
2. 在你的 fork 里新建文件：
   `data/plugins/zz19940402__dsh-news-skill.yml`
3. 内容复制本目录的 `SUBMISSION.yml`：

```yaml
url: https://github.com/zz19940402/dsh-news-skill
name: zz19940402/dsh-news-skill
category: skill
description:
  en: 'DSH skill that fetches dated news briefings from public RSS and live feeds in four categories: international, domestic economy, domestic tech, and global tech, five items each with title, source, time and original link.'
  zh: 'DSH 新闻技能：按日期从公开 RSS 与快讯接口抓取国际经济、国内经济、国内科技、国际科技四类新闻，每类五条，含标题、来源、时间与原始链接。'
```

4. Commit，然后开 PR 到上游 `main`
5. CI 跑绿 + 维护者审核（会实际读你的仓库核对描述与代码），通常一天内合并

---

## 合并后会发生什么

- awesome-dsh-plugin 的 README 自动生成条目
- 站点 awesome-dsh-plugin.com 更新
- dshmarket 插件市场自动收录（你说“同步到插件市场”指的就是这个）
- DSH 用户可用 `dsh plugin add zz19940402/dsh-news-skill` 安装

---

## 已完成的准备（不用你管）

- ✅ 所有写死的本机路径已清除（SKILL.md / README / fetch_news.ps1）
- ✅ Python 探测改成多候选（环境变量 → PATH 真实 python → DSH 运行时），并排除 Windows 商店占位符
- ✅ `cordis.patch.yml` 用 `createRequire(baseUrl)` 相对解析，无绝对路径
- ✅ locale 中英双语、图标、README 齐备
- ✅ git 仓库已初始化并 commit
- ✅ 投稿 YAML 已生成并校验格式

## 我没做的（需要你）

- 建 GitHub 仓库（要你的账号）
- push（要你的凭据）
- 加 topic（网页操作）
- 提 PR（要你的 fork）

---

## 一个诚实的提醒

CI 会核对描述是否属实。你的描述写了四类各五条——代码确实做到了（我实测 0 错误、四类各 5 条）。但有两个已知短板写在 README 和 SKILL.md 的"已知限制"里：

- 国内科技类混财报股价（36氪快讯无关键词过滤）
- 国际类偏财经快讯

这不影响上架（描述没夸大这两类的"纯度"），但维护者读代码时可能会问。如实回答即可。
