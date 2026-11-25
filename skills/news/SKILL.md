---
name: news
description: "获取指定日期（默认当天）的国际新闻、国内经济新闻、国内科技新闻、国际科技新闻，每类默认 5 条。使用公开 RSS 与快讯接口检索，返回标题、链接、来源、发布时间和摘要；只使用脚本能验证的新闻，不编造。Also supplements the four feeds with a web search for major breaking news of the day. Use when the user asks for today's or a given day's international news, domestic economy news, domestic tech news, or global tech news."
metadata:
  version: "0.2.0"
  language: zh-CN
---

# News

获取以下四类新闻，每类默认 5 条：

1. **国际经济新闻** `international`
2. **国内经济新闻** `domestic_economy`
3. **国内科技新闻** `domestic_tech`
4. **国际科技新闻** `global_tech`

## 执行方式

脚本 `scripts/fetch_news.ps1` 位于本 skill 包内。加载本 skill 时，工具结果会给出 **Base directory**（技能根目录）；用它加上 `../scripts/fetch_news.ps1` 得到脚本绝对路径（skill 目录在 `skills/news/`，脚本在包根 `scripts/`）：

```powershell
# $skillDir = <本次 skill 工具结果里的 Base directory>，例如 <repo>/skills/news
$script = Join-Path (Split-Path $skillDir -Parent) 'scripts/fetch_news.ps1'
& $script -Category all -Count 5
```

若你在仓库根目录的终端里手动运行，直接用相对路径：

```powershell
& './scripts/fetch_news.ps1' -Category all -Count 5
```

脚本输出 UTF-8 JSON，含 `international`、`domestic_economy`、`domestic_tech`、`global_tech`、`date`、`errors`。AI 只应基于脚本返回的内容整理结果；如果某类不足 5 条，明确说明“该源当天可验证的条目不足”，不要补编新闻。

### 指定日期

`-Date yyyy-MM-dd`，留空为今天：

```powershell
& $script -Category all -Count 5 -Date 2026-11-23
```

历史日期依赖快讯源的分页回溯（每页约 3.5 小时，最多 30 页 ≈ 4 天）。更早的日期会拿不满条数，需如实说明。

### 只取某一类

```powershell
& $script -Category international -Count 5
& $script -Category economy       -Count 5
& $script -Category tech          -Count 5
& $script -Category global_tech   -Count 5
```
### 重大新闻兜底（必做）

脚本的固定源覆盖窄：航天发射、重大时政、灾害、突发事件常落在盲区（例：2026-11-25 神舟二十四号发射成功，四个源全漏）。所以每次生成新闻简报，**在脚本结果之外，必须再用联网搜索补一次当天重大新闻**：

- 搜当天日期 + "重大新闻" / "突发" / "航天发射" 等，或直接用当天日期搜头条
- 只采纳能给出**明确来源链接**且日期为当天的条目；搜不到的不要编
- 把搜到的重大新闻单独列一节 **「重大新闻（搜索补充）」** 放在四类之前，每条给标题、来源、链接
- 与脚本重复的条目不重复列出
- 如果搜索无结果或工具不可用，如实说明"未能做搜索补充"，不要假装覆盖全面

脚本结果照常按四类展示，搜索补充不混入四类——两者来源性质不同（脚本=固定源可验证，搜索=全网索引需甄别）。
## 数据源

| 类别 | 源 |
|---|---|
| international | 华尔街见闻 global-channel、WSJ World RSS |
| domestic_economy | 华尔街见闻 a-stock / hk-stock / forex 频道、经济文章、36氪快讯（经济词筛） |
| domestic_tech | 36氪快讯、少数派 |
| global_tech | The Verge、Ars Technica、MIT Technology Review、Solidot |

`global_tech` 的英文标题在展示时翻译成中文，但保留原文标题与原始链接。

## 输出要求

- 用中文按类分组展示。
- 每条包含：标题、来源、日期、链接。
- 保留脚本返回的原链接，不要缩短或改写链接。
- 日期按中国本地时间判断目标日期。
- 如果 RSS 被网络拦截或无当天条目，如实说明失败原因。

## 已知限制

- **国际类偏财经快讯。** 华尔街见闻 global-channel 是市场资讯，地缘政治类要闻覆盖不足。
- **科技类只有少数派。** 36氪快讯只剩最近 20 条且全是当天的，无法回溯，且 tech 类没有关键词过滤（经济类有 `Test-DomesticEconomicItem`），会把财报、股价混进来。
- **Hacker News / TechCrunch 被网络阻断**，不可用。
- 脚本的 HTTP 层走 DSH 捆绑 Python（`fetch_http.py`），因为 PowerShell 5.1 的 `Invoke-WebRequest` 在本机 Schannel 上对每个 HTTPS 请求都报 `SEC_E_NO_CREDENTIALS`。
