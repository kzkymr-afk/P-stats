#!/usr/bin/env bash
# `P-stats/Design/` 以外の Swift で、不透明度の数値リテラルや `Color(red:` が紛れ込んでいないか確認する。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# 数値リテラルの直書きのみ検出（`Color.white.opacity(DesignTokens...)` や `Color(red: r, green: g` は対象外）
pat='Color\.white\.opacity\(\s*[0-9]|Color\.black\.opacity\(\s*[0-9]|Color\(red:\s*[0-9]'
if ! grep -RsnE --include='*.swift' "$pat" P-stats 2>/dev/null | grep -v '/Design/' >"$tmp"; then
  :
fi

if [[ -s "$tmp" ]]; then
  echo "デザイン数値リテラルが Design 外で検出されました（ファイル:行）:"
  cat "$tmp"
  exit 1
fi

echo "OK: Design フォルダ外に不透明度の数値直書き / Color(red: はありません。"
