param(
    [ValidateSet('all', 'international', 'economy', 'tech', 'global_tech')]
    [string]$Category = 'all',

    [ValidateRange(1, 20)]
    [int]$Count = 5,

    # 目标日期（yyyy-MM-dd）。留空 = 今天。RSS/快讯源只能回溯最近几十条，
    # 所以较早的日期可能拿不满 Count 条，这时如实报告而不是补编。
    [string]$Date = ''
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
} catch {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

if ([string]::IsNullOrWhiteSpace($Date)) {
    $today = (Get-Date).Date
} else {
    $parsed = [datetime]::MinValue
    $ok = [datetime]::TryParseExact($Date.Trim(), 'yyyy-MM-dd', [cultureinfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None, [ref]$parsed)
    if (-not $ok) { throw "日期格式应为 yyyy-MM-dd，收到: $Date" }
    $today = $parsed.Date
}
$errors = [System.Collections.Generic.List[object]]::new()

function Convert-HtmlText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }

    $text = $Value -replace '<script\b[^>]*>.*?</script>', '' -replace '<style\b[^>]*>.*?</style>', ''
    $text = $text -replace '<[^>]+>', ' '
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    return ($text -replace '\s+', ' ').Trim()
}

# --- HTTP transport -----------------------------------------------------------
# Invoke-WebRequest in PowerShell 5.1 rides on Schannel, which fails on this host
# with SEC_E_NO_CREDENTIALS for every HTTPS request ("基础连接已经关闭"). The bundled
# CPython carries its own OpenSSL stack, so the fetch is delegated to it and the
# body comes back through a temp file (avoids the OEM-code-page mangling that
# hits captured child-process stdout).
$script:PythonExe = $null

function Get-PythonExe {
    if ($script:PythonExe) { return $script:PythonExe }
    $candidates = @()
    # 1) 显式环境变量优先
    if ($env:NEWS_PYTHON)  { $candidates += $env:NEWS_PYTHON }
    if ($env:DSH_PYTHON)   { $candidates += $env:DSH_PYTHON }
    # 2) PATH 上的 python / python3 —— 但要排除 Windows 商店的占位符，
    #    它 --version 返回 0 却无法执行脚本（实际报 "Python was not found"）。
    foreach ($n in @('python3', 'python')) {
        $cmd = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        $path = $cmd.Source
        if ($path -like '*WindowsApps*') { continue }
        $probeOut = & $path -c "print(1)" 2>&1
        if ($LASTEXITCODE -eq 0 -and "$probeOut" -match '1') { $candidates += $path }
    }
    # 3) DSH 捆绑运行时的常见位置（本机可用；别人没有也不影响）
    $dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
    $candidates += Join-Path $dshHome 'dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        $probe = & $candidate --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $script:PythonExe = $candidate
            return $candidate
        }
    }
    return $null
}

function Get-HttpText {
    param([string]$Url)

    $python = Get-PythonExe
    if (-not $python) {
        throw '找不到可用的 Python（设置了 DSH_PYTHON 或使用 DSH 捆绑运行时）'
    }
    $helper = Join-Path $PSScriptRoot 'fetch_http.py'
    if (-not (Test-Path -LiteralPath $helper)) {
        throw "缺少抓取脚本: $helper"
    }
    $tempFile = Join-Path $PSScriptRoot ('http-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $output = & $python $helper $Url $tempFile 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw ("抓取失败: " + ($output -join ' '))
        }
        return (Get-Content -LiteralPath $tempFile -Raw -Encoding UTF8)
    } finally {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-HostOrSource {
    param(
        [string]$Url,
        [string]$Fallback
    )

    if ($Fallback) {
        return $Fallback
    }
    try {
        return ([uri]$Url).Host
    } catch {
        return ''
    }
}

function New-NewsItem {
    param(
        [string]$Category,
        [string]$Title,
        [string]$Url,
        [string]$Source,
        [datetimeoffset]$Published,
        [string]$Summary,
        [string]$Feed,
        [datetime]$Today
    )

    if ($Summary.Length -gt 220) {
        $Summary = $Summary.Substring(0, 220).Trim() + '...'
    }

    return [pscustomobject]@{
        category     = $Category
        title        = $Title
        url          = $Url
        source       = $Source
        published    = $Published.ToLocalTime().ToString('yyyy-MM-dd HH:mm')
        published_at = $Published.ToLocalTime().ToString('o')
        summary      = $Summary
        feed         = $Feed
        is_today     = [bool]($Published.ToLocalTime().Date -eq $Today.Date)
    }
}

function Get-RssItems {
    param(
        [string]$Category,
        [string]$Url,
        [datetime]$Today,
        [string]$FallbackSource = ''
    )

    $result = @()
    $content = Get-HttpText -Url $Url
    $xml = New-Object System.Xml.XmlDocument
    $xml.LoadXml($content)
    $nodes = $xml.SelectNodes('/rss/channel/item')
    if ($nodes.Count -eq 0) {
        $nodes = $xml.SelectNodes('//*[local-name()="item" or local-name()="entry"]')
    }

    foreach ($node in $nodes) {
        $titleNode = $node.SelectSingleNode('title')
        $linkNode = $node.SelectSingleNode('link')
        $dateNode = $node.SelectSingleNode('pubDate')
        if ($null -eq $dateNode) {
            $dateNode = $node.SelectSingleNode('published')
        }
        if ($null -eq $dateNode) {
            $dateNode = $node.SelectSingleNode('updated')
        }
        # Atom（The Verge 等）用 <content>，RSS 用 <description>/<summary>；三种都要兜住，
        # 否则 SelectSingleNode 返回 null，后面取 .InnerText 会直接抛错整源作废。
        $descNode = $node.SelectSingleNode('description')
        if ($null -eq $descNode) {
            $descNode = $node.SelectSingleNode('summary')
        }
        if ($null -eq $descNode) {
            $descNode = $node.SelectSingleNode('content')
        }
        $sourceNode = $node.SelectSingleNode('source')

        $title = ''
        if ($titleNode) { $title = Convert-HtmlText $titleNode.InnerText }
        $link = ''
        if ($linkNode) {
            $link = $linkNode.InnerText.Trim()
            if ([string]::IsNullOrWhiteSpace($link) -and $linkNode.Attributes['href']) {
                $link = $linkNode.Attributes['href'].Value.Trim()
            }
        }
        $summary = ''
        if ($descNode) { $summary = Convert-HtmlText $descNode.InnerText }

        # 来源优先级：feed 自带的 <source> → 调用方给的友好名 → 域名兜底。
        # 原顺序把域名放在友好名之前，导致 "36氪" 被显示成 "www.36kr.com"。
        $source = ''
        if ($sourceNode) { $source = Convert-HtmlText $sourceNode.InnerText }
        if ([string]::IsNullOrWhiteSpace($source)) { $source = $FallbackSource }
        if ([string]::IsNullOrWhiteSpace($source)) { $source = Get-HostOrSource -Url $link -Fallback '' }

        $published = $null
        if ($dateNode -and -not [string]::IsNullOrWhiteSpace($dateNode.InnerText)) {
            try {
                $published = [datetimeoffset]::Parse($dateNode.InnerText.Trim(), [cultureinfo]::InvariantCulture)
            } catch {
                $published = $null
            }
        }
        if ($null -eq $published) { continue }
        if ($title -and $link) {
            $result += New-NewsItem -Category $Category -Title $title -Url $link -Source $source -Published $published -Summary $summary -Feed $Url -Today $Today
        }
    }

    return $result
}

# 快讯接口每页 100 条、约 3.5 小时。next_cursor 可以一直往更早翻，所以取历史
# 日期时按页回溯，翻过目标日期就停 —— 不设上限的话昨天之前的新闻永远拿不到。
function Get-WscnLiveItems {
    param(
        [string]$Category,
        [string]$Channel,
        [datetime]$Today,
        [int]$Limit = 100,
        [int]$MaxPages = 30
    )

    $result = @()
    $cursor = $null
    $targetEnd = $Today.Date.AddDays(1)

    for ($page = 0; $page -lt $MaxPages; $page++) {
        $url = "https://api-one-wscn.awtmt.com/apiv1/content/lives?channel=$Channel&limit=$Limit"
        if ($cursor) { $url += "&cursor=$cursor" }

        try {
            $json = (Get-HttpText -Url $url) | ConvertFrom-Json
        } catch {
            break
        }
        $items = @($json.data.items)
        if ($items.Count -eq 0) { break }

        $oldest = [datetimeoffset]::MaxValue
        foreach ($item in $items) {
            $published = [datetimeoffset]::FromUnixTimeSeconds([long]$item.display_time)
            if ($published -lt $oldest) { $oldest = $published }

            $title = Convert-HtmlText $item.title
            if ([string]::IsNullOrWhiteSpace($title)) {
                $title = Convert-HtmlText $item.content_text
                if ($title.Length -gt 100) {
                    $title = $title.Substring(0, 100).Trim() + '...'
                }
            }
            $link = [string]$item.uri
            if ($link -match '^wscn://') {
                $link = ''
            }
            $summary = Convert-HtmlText $item.content_text

            if ($title -and $link) {
                $result += New-NewsItem -Category $Category -Title $title -Url $link -Source '华尔街见闻' -Published $published -Summary $summary -Feed $url -Today $Today
            }
        }

        if ($oldest -lt $targetEnd) { break }
        $cursor = $json.data.next_cursor
        if (-not $cursor) { break }
    }

    return $result
}

function Get-WscnArticleItems {
    param(
        [string]$Category,
        [string]$Channel,
        [datetime]$Today,
        [int]$Limit = 80
    )

    $result = @()
    $url = "https://api-one-wscn.awtmt.com/apiv1/content/articles?category=$Channel&limit=$Limit"
    $content = Get-HttpText -Url $url
    $json = $content | ConvertFrom-Json

    foreach ($item in $json.data.items) {
        if ($item.is_in_vip_privilege) {
            continue
        }
        $published = [datetimeoffset]::FromUnixTimeSeconds([long]$item.display_time)
        $link = [string]$item.uri
        $summary = Convert-HtmlText $item.content_short

        if ($item.title -and $link) {
            $result += New-NewsItem -Category $Category -Title $item.title -Url $link -Source '华尔街见闻' -Published $published -Summary $summary -Feed $url -Today $Today
        }
    }

    return $result
}

function Normalize-Title {
    param([string]$Text)
    return (($Text -replace '[\p{P}\p{S}\s]', '').ToLowerInvariant())
}

function Select-FromItems {
    param(
        [object[]]$Items,
        [int]$Count
    )

    $seenUrl = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $seenTitle = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $selected = @()

    $items = $items |
        Where-Object { $_.title -and $_.url -and $_.is_today } |
        Sort-Object { [datetimeoffset]::Parse($_.published_at).UtcDateTime } -Descending

    foreach ($item in $items) {
        $titleKey = Normalize-Title $item.title
        if ($seenUrl.Add($item.url) -and $titleKey -and $seenTitle.Add($titleKey)) {
            $selected += $item
            if ($selected.Count -ge $Count) {
                break
            }
        }
    }

    return $selected
}

function Test-DomesticEconomicItem {
    param([object]$Item)

    $text = "$($Item.title) $($Item.summary)"
    $hasChinaSignal = $text -match '中国|国内|A股|港股|沪深|上证|深证|创业板|科创板|人民币|中概股|证监会|国家统计局|香港|腾讯|阿里巴巴|京东|拼多多|百度|比亚迪|宁德时代|小米|小鹏|理想汽车|银河证券|中信证券|国泰君安'
    $hasEconomicSignal = $text -match '股|债|汇率|人民币|央行|货币|财政|消费|出口|进口|工业|制造|经济|宏观|GDP|CPI|PPI|PMI|就业|通胀|基金|期货|上市公司|IPO|分红|营收|利润|供应链|新能源|银行|证券|融资|上市|并购|招股'
    return [bool]($hasChinaSignal -and $hasEconomicSignal)
}

function Invoke-Source {
    param(
        [string]$Label,
        [scriptblock]$Action,
        [string]$Category,
        [System.Collections.Generic.List[object]]$Errors
    )

    try {
        return & $Action
    } catch {
        $Errors.Add([pscustomobject]@{
            category = $Category
            feed     = $Label
            error    = $_.Exception.Message
        })
        return @()
    }
}

$result = @{
    date             = $today.ToString('yyyy-MM-dd')
    timezone         = (Get-TimeZone).Id
    international    = @()
    domestic_economy = @()
    domestic_tech    = @()
    global_tech      = @()
    errors           = $errors
}

if ($Category -in @('all', 'international')) {
    $internationalItems = @()
    $internationalItems += Invoke-Source -Label '华尔街见闻·全球快讯' -Category 'international' -Errors $errors -Action {
        Get-WscnLiveItems -Category 'international' -Channel 'global-channel' -Today $today
    }
    $internationalItems += Invoke-Source -Label 'WSJ World RSS' -Category 'international' -Errors $errors -Action {
        Get-RssItems -Category 'international' -Url 'https://feeds.a.dj.com/rss/RSSWorldNews.xml' -Today $today
    }
    $result.international = Select-FromItems -Items $internationalItems -Count $Count
}

if ($Category -in @('all', 'economy')) {
    $economyItems = @()
    foreach ($channel in @('a-stock-channel', 'hk-stock-channel', 'forex-channel')) {
        $economyItems += Invoke-Source -Label "华尔街见闻·$channel" -Category 'domestic_economy' -Errors $errors -Action {
            Get-WscnLiveItems -Category 'domestic_economy' -Channel $channel -Today $today
        }
    }
    $economyItems += Invoke-Source -Label '华尔街见闻·经济文章' -Category 'domestic_economy' -Errors $errors -Action {
        Get-WscnArticleItems -Category 'domestic_economy' -Channel 'economy' -Today $today
    }
    $economyItems += Invoke-Source -Label '36氪快讯·经济筛' -Category 'domestic_economy' -Errors $errors -Action {
        Get-RssItems -Category 'domestic_economy' -Url 'https://rsshub.rssforever.com/36kr/newsflashes' -Today $today -FallbackSource '36氪'
    }
    $economyItems = @($economyItems | Where-Object { Test-DomesticEconomicItem -Item $_ })
    $result.domestic_economy = Select-FromItems -Items $economyItems -Count $Count
}

if ($Category -in @('all', 'tech')) {
    $techItems = @()
    $techItems += Invoke-Source -Label '36氪快讯 RSS' -Category 'domestic_tech' -Errors $errors -Action {
        Get-RssItems -Category 'domestic_tech' -Url 'https://rsshub.rssforever.com/36kr/newsflashes' -Today $today -FallbackSource '36氪'
    }
    $techItems += Invoke-Source -Label '少数派 RSS' -Category 'domestic_tech' -Errors $errors -Action {
        Get-RssItems -Category 'domestic_tech' -Url 'https://www.sspai.com/feed' -Today $today -FallbackSource '少数派'
    }
    $result.domestic_tech = Select-FromItems -Items $techItems -Count $Count
}

if ($Category -in @('all', 'global_tech')) {
    $globalTechItems = @()
    $globalTechItems += Invoke-Source -Label 'The Verge' -Category 'global_tech' -Errors $errors -Action {
        Get-RssItems -Category 'global_tech' -Url 'https://www.theverge.com/rss/index.xml' -Today $today -FallbackSource 'The Verge'
    }
    $globalTechItems += Invoke-Source -Label 'Ars Technica' -Category 'global_tech' -Errors $errors -Action {
        Get-RssItems -Category 'global_tech' -Url 'https://feeds.arstechnica.com/arstechnica/index' -Today $today -FallbackSource 'Ars Technica'
    }
    $globalTechItems += Invoke-Source -Label 'MIT Tech Review' -Category 'global_tech' -Errors $errors -Action {
        Get-RssItems -Category 'global_tech' -Url 'https://www.technologyreview.com/feed/' -Today $today -FallbackSource 'MIT Tech Review'
    }
    $globalTechItems += Invoke-Source -Label 'Solidot' -Category 'global_tech' -Errors $errors -Action {
        Get-RssItems -Category 'global_tech' -Url 'https://www.solidot.org/index.rss' -Today $today -FallbackSource 'Solidot'
    }
    $result.global_tech = Select-FromItems -Items $globalTechItems -Count $Count
}

$result | ConvertTo-Json -Depth 6
