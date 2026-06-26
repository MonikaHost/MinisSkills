#!/bin/sh
# ensure_tab.sh
# 确保浏览器有已登录的闲鱼 tab，输出 tab_id。
# 若未登录，自动打开闲鱼并用 minis-open 提示用户登录，等待最多 120s。
#
# 环境变量：
#   TAB_ID  — 若已知 tab_id，跳过自动检测（仍会验证登录态）

# ---------- 辅助：检测某 tab 的登录状态 ----------
check_login() {
  local tid="$1"
  minis-browser-use execute_js --tab-id "$tid" \
    --script 'return window.location.href.includes("passport") ? "not_login" : (window.lib && window.lib.mtop ? "ok" : "loading")' \
    --compact -q 2>/dev/null \
    | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('text','').split('\n')[0].strip())
except Exception:
    print('error')
" 2>/dev/null
}

# ---------- 辅助：扫描所有 tab，找含有闲鱼域名的 tab ----------
# list_tabs 返回格式：{"success":true,"text":"Open tabs:\n  Tab 0: 标题 — https://... *"}
find_logged_tab() {
  local raw
  raw=$(minis-browser-use list_tabs --compact -q 2>/dev/null)
  python3 -c "
import json, sys, re
try:
    d = json.loads(sys.argv[1])
    text = d.get('text', '')
    for line in text.split('\n'):
        m = re.search(r'Tab (\d+):.*?(https?://\S+)', line)
        if m:
            tab_id = m.group(1)
            url = m.group(2).rstrip('* ')
            if 'goofish.com' in url or 'xianyu' in url:
                print(tab_id)
                break
except Exception:
    pass
" "$raw" 2>/dev/null
}

# ---------- 主流程 ----------

# 若调用方已指定 TAB_ID，直接验证并返回
if [ -n "$TAB_ID" ]; then
  STATUS=$(check_login "$TAB_ID")
  if [ "$STATUS" = "ok" ]; then
    echo "$TAB_ID"
    exit 0
  fi
  # 已指定但未登录，走下面的等待流程
  TRY_TAB="$TAB_ID"
else
  TRY_TAB=$(find_logged_tab)
fi

# 若找到 tab，检查是否已登录
if [ -n "$TRY_TAB" ]; then
  STATUS=$(check_login "$TRY_TAB")
  if [ "$STATUS" = "ok" ]; then
    echo "$TRY_TAB"
    exit 0
  fi
fi

# ---------- 未登录：自动 navigate 到闲鱼 ----------
echo "⏳ 未检测到已登录的闲鱼页面，正在打开…" >&2

# 优先复用已有 tab，没有则打开新页面
if [ -n "$TRY_TAB" ]; then
  minis-browser-use navigate --tab-id "$TRY_TAB" --url "https://www.goofish.com" --compact -q >/dev/null 2>&1
else
  minis-browser-use navigate --url "https://www.goofish.com" --compact -q >/dev/null 2>&1
  TRY_TAB=$(find_logged_tab)
fi

# 同时用 minis-open 让用户看到浏览器
minis-open "https://www.goofish.com" >/dev/null 2>&1

echo "🐟 已打开闲鱼，请在浏览器中完成登录，最多等待 120 秒…" >&2

# ---------- 轮询等待登录完成（每 5s 一次，最多 24 次）----------
i=0
while [ $i -lt 24 ]; do
  sleep 5
  i=$((i + 1))

  # 每次重新扫 tab，以防用户在新 tab 登录
  if [ -z "$TRY_TAB" ]; then
    TRY_TAB=$(find_logged_tab)
  fi
  [ -z "$TRY_TAB" ] && continue

  STATUS=$(check_login "$TRY_TAB")
  if [ "$STATUS" = "ok" ]; then
    echo "✅ 登录成功！" >&2
    echo "$TRY_TAB"
    exit 0
  fi
done

echo "❌ 等待超时，未检测到登录。请手动登录后重试。" >&2
exit 1
