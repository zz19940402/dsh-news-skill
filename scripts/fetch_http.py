"""fetch_http.py - HTTP fetcher used by fetch_news.ps1.

Windows PowerShell 5.1's Invoke-WebRequest goes through Schannel, which fails
on this host with SEC_E_NO_CREDENTIALS for every HTTPS request. The bundled
CPython uses its own OpenSSL stack, so routing the fetch through it works.

Usage:
    python fetch_http.py <url> <output-file>

Writes the decoded body to <output-file> as UTF-8. Exit code 1 on failure,
with the reason on stderr.
"""
import gzip
import sys
import urllib.request
import zlib

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
)
HEADERS = {
    "User-Agent": USER_AGENT,
    "Accept": "application/json, application/rss+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.7",
    "Cache-Control": "no-cache",
}

# Try the charset the server declares first, then the two encodings that
# actually appear in Chinese feeds. latin-1 never raises, so it is the floor.
FALLBACK_ENCODINGS = ("utf-8", "gb18030", "big5")


def decode(raw, content_type):
    declared = None
    if "charset=" in content_type.lower():
        declared = content_type.lower().split("charset=")[-1].split(";")[0].strip().strip('"\'')
    for candidate in (declared, *FALLBACK_ENCODINGS):
        if not candidate:
            continue
        try:
            return raw.decode(candidate)
        except (LookupError, UnicodeDecodeError):
            continue
    return raw.decode("utf-8", "replace")


def fetch(url):
    request = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(request, timeout=20) as response:
        raw = response.read()
        encoding = (response.headers.get("Content-Encoding") or "").lower()
        content_type = response.headers.get("Content-Type") or ""
    if "gzip" in encoding:
        raw = gzip.decompress(raw)
    elif "deflate" in encoding:
        raw = zlib.decompress(raw)
    return decode(raw, content_type)


def main(argv):
    if len(argv) != 3:
        print("usage: fetch_http.py <url> <output-file>", file=sys.stderr)
        return 2
    url, out_path = argv[1], argv[2]
    try:
        text = fetch(url)
    except Exception as exc:  # noqa: BLE001 - report any transport failure verbatim
        print(f"{type(exc).__name__}: {exc}", file=sys.stderr)
        return 1
    with open(out_path, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
