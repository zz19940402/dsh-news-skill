# News skill for DSH

A DeepSeek Harness skill bundle that fetches dated news briefings from public RSS and live feeds. Nothing is invented: if a feed is unreachable or has no item for the requested date, the skill says so.

## What it adds

A `news` skill with four categories, five items each:

| Key | Category | Sources |
|---|---|---|
| `international` | International / global economy | Wallstreetcn global channel, WSJ World RSS |
| `domestic_economy` | Domestic economy | Wallstreetcn A-share / HK / forex channels, economy articles, 36Kr (economic filter) |
| `domestic_tech` | Domestic tech | 36Kr, SSPAI |
| `global_tech` | Global tech | The Verge, Ars Technica, MIT Technology Review, Solidot |

Each item returns title, source, timestamp, and the original link.

## How to use

Ask naturally, or name the skill:

```
获取今天的新闻
用 news skill 获取昨天的国际科技新闻
```

The skill runs the bundled fetcher:

```powershell
& './scripts/fetch_news.ps1' -Category all -Count 5
```

Options:

- `-Category`: `all` / `international` / `economy` / `tech` / `global_tech`
- `-Count`: 1–20, default 5
- `-Date yyyy-MM-dd`: a target date, default today. Historical dates rely on cursor paging through the live feed (about 3.5 hours per page, 30 pages max, roughly 4 days back).

## How it is installed

This is a `dsh.bundle` package. Its `cordis.patch.yml` inserts a `@deepseek-ai/dsh-skill-filesystem` provider whose `bundledSkillDir` resolves to this package's `skills/` folder through `createRequire(baseUrl)`, so it stays portable after a local-directory install. There is no machine-specific absolute path in the patch.

## Notes

- HTTP fetch goes through the bundled CPython (`scripts/fetch_http.py`). PowerShell 5.1's `Invoke-WebRequest` fails on this host with Schannel `SEC_E_NO_CREDENTIALS` for every HTTPS request.
- Hacker News and TechCrunch are network-blocked here and are not included.
- Installing this plugin runs local scripts with your own permissions. Review `scripts/` before installing if the source is not yours.
