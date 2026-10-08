#!/usr/bin/env bash
#
# 检查本地化：源码里所有 L("…") / LF("…") 用到的 key，以及主题名、配色名、符号标记名
# 这些动态 key，是否都在 zh-Hans 的 Localizable.strings 里有翻译。
# 只读检查，不修改任何文件。加 -v 额外列出 strings 文件里多余的 key。
#
set -euo pipefail
cd "$(dirname "$0")/.."

ZH="Sources/FreeMind/Resources/zh-Hans.lproj/Localizable.strings"
plutil -lint "$ZH" >/dev/null || { echo "ERROR: $ZH 语法错误"; plutil -lint "$ZH"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

{
    # 源码中的静态 key
    grep -rhoE '\bLF?\("([^"\\]|\\.)*"' Sources | sed -E 's/^LF?\("//; s/"$//'
    # 动态 key：内置风格名、配色名、符号标记名
    grep -hoE 'name: "[^"]+"' Sources/FreeMind/Theme/BuiltinThemes.swift | sed -E 's/name: "//; s/"$//'
    grep -hoE '^[[:space:]]*\("[A-Za-z]+", \[' Sources/FreeMind/Inspector/MapInspector.swift \
        | sed -E 's/^[[:space:]]*\("//; s/", \[$//'
    grep -hoE 'titleKey: "[^"]+"' Sources/FreeMind/Model/Marker.swift | sed -E 's/titleKey: "//; s/"$//'
} | sort -u > "$tmp/used"

# 已翻译的 key
grep -oE '^"([^"\\]|\\.)*"[[:space:]]*=' "$ZH" | sed -E 's/^"//; s/"[[:space:]]*=$//' | sort -u > "$tmp/have"

missing=$(comm -23 "$tmp/used" "$tmp/have")
unused=$(comm -13 "$tmp/used" "$tmp/have")

status=0
if [[ -n "$missing" ]]; then
    echo "缺少中文翻译的 key："
    while IFS= read -r key; do echo "  - $key"; done <<< "$missing"
    status=1
fi
if [[ -n "$unused" && "${1:-}" == "-v" ]]; then
    echo "strings 文件里没有被源码引用的 key："
    while IFS= read -r key; do echo "  - $key"; done <<< "$unused"
fi
if [[ $status -eq 0 ]]; then
    echo "✓ 本地化完整：$(wc -l < "$tmp/used" | tr -d ' ') 个 key 都有中文翻译"
fi
exit $status
