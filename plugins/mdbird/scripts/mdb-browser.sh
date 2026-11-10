#!/usr/bin/env bash
# mdbird 用のブラウザ操作（browser-use 1.0 以降）
#
# browser-use 1.0 で CLI が変わった。
#   - open / eval / scroll / screenshot / close のサブコマンドは廃止。Python を標準入力で渡す
#   - 既定では「いま動いている Chrome」に CDP でつなぐ
# 既定のままだと、利用者が普段使っている Chrome のタブへ入り込む。そこで取得ごとに
# 専用の headless Chrome を空いている番号で立て、BU_CDP_URL でそこだけにつなぐ。
#
# Claude の Bash 呼び出しは環境変数を持ち越さないので、番号や PID は状態ファイルに置く。
# 第1引数のセッション名（ツイート ID を使う）で、同時に走る取得を分ける。
#
# 使い方:
#   mdb-browser.sh check
#   mdb-browser.sh start      <session>          # Chrome を立て、クッキーを入れる
#   mdb-browser.sh open       <session> <url>
#   mdb-browser.sh js         <session> [<js>]   # 省略時は標準入力から読む
#   mdb-browser.sh scroll     <session>          # 下端まで読み込ませてから上へ戻る
#   mdb-browser.sh screenshot <session> <path>
#   mdb-browser.sh stop       <session>          # Chrome を止め、作業用のファイルを消す
#
# 環境変数:
#   MDBIRD_COOKIES   クッキーの JSON（既定: ~/.config/mdbird/x_cookies.json → x-cookies.json）
#   MDBIRD_CHROME    Chrome の実行ファイル（既定: 自動で探す）
#   MDBIRD_MAX_LIFE  停止し忘れたときに自動で止めるまでの秒数（既定: 1800）
set -uo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/mdbird"
MAX_LIFE="${MDBIRD_MAX_LIFE:-1800}"

die(){ echo "[mdb-browser] $*" >&2; exit 1; }

find_chrome(){
  if [ -n "${MDBIRD_CHROME:-}" ]; then echo "$MDBIRD_CHROME"; return; fi
  local c
  for c in google-chrome google-chrome-stable chromium chromium-browser; do
    command -v "$c" >/dev/null 2>&1 && { command -v "$c"; return; }
  done
  c="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  [ -x "$c" ] && { echo "$c"; return; }
  return 1
}

check(){
  command -v browser-use >/dev/null 2>&1 || die "browser-use が見つからない"
  command -v python3 >/dev/null 2>&1 || die "python3 が見つからない"
  # 1.0 以降は --version に browser-harness の版が並ぶ。旧版のサブコマンドとは互換がない
  browser-use --version 2>/dev/null | grep -q 'browser-harness' \
    || die "browser-use が 1.0 より古い（uv tool upgrade browser-use で更新）"
  find_chrome >/dev/null || die "Chrome / Chromium が見つからない（MDBIRD_CHROME で指定できる）"
  echo "ok"
}

valid_session(){
  [[ "${1:-}" =~ ^[A-Za-z0-9_-]{1,40}$ ]] || die "セッション名は英数字・_・- の40字以内（ツイート ID を使う）"
}

state_file(){ echo "$CACHE_DIR/session-$1.env"; }

# 状態ファイルを読み、browser-use が使う環境変数を立てる
load_state(){
  local f; f=$(state_file "$1")
  [ -f "$f" ] || die "セッション $1 が無い（先に start を実行する）"
  PORT="" PID="" PROFILE=""   # 状態ファイルで決まる
  # shellcheck source=/dev/null
  . "$f"
  export BU_NAME="mdbird-$1" BU_CDP_URL="http://127.0.0.1:$PORT" BH_TAB_MARKER=0 BH_RECORD=0
}

bu(){ browser-use 2>&1; }

start(){
  local s=$1 chrome ver ua port profile pid
  check >/dev/null
  chrome=$(find_chrome)
  mkdir -p "$CACHE_DIR"
  [ -f "$(state_file "$s")" ] && stop "$s" >/dev/null 2>&1
  port=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
  profile=$(mktemp -d "$CACHE_DIR/chrome-XXXXXX")
  # headless の既定の UA は "HeadlessChrome" を名乗り、X に弾かれうるので普通の UA にする
  ver=$("$chrome" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+){3}' | head -1)
  ua="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${ver:-140.0.0.0} Safari/537.36"
  # 新しいセッションで起動して PID（＝プロセスグループの番号）を受け取る。止めるときはグループごと止める
  pid=$(python3 - "$chrome" --headless=new --remote-debugging-port="$port" --user-data-dir="$profile" \
    --no-first-run --no-default-browser-check --disable-gpu --window-size=1400,2000 \
    --disable-blink-features=AutomationControlled --user-agent="$ua" about:blank <<'PY'
import subprocess, sys
p = subprocess.Popen(sys.argv[1:], start_new_session=True, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print(p.pid)
PY
)
  printf 'PORT=%s\nPID=%s\nPROFILE=%q\n' "$port" "$pid" "$profile" > "$(state_file "$s")"
  local up=0
  for _ in $(seq 1 40); do
    curl -sf "http://127.0.0.1:$port/json/version" >/dev/null 2>&1 && { up=1; break; }
    sleep 0.25
  done
  [ "$up" = 1 ] || { stop "$s" >/dev/null 2>&1; die "専用の Chrome が立ち上がらない"; }

  # 停止し忘れたときの保険。MAX_LIFE 秒たったら止める
  nohup bash "$0" _expire "$s" "$pid" "$MAX_LIFE" >/dev/null 2>&1 &

  load_state "$s"
  MD_COOKIES="${MDBIRD_COOKIES:-}" bu <<'PY' | tail -1
import os, json
# 専用タブは「裏のタブ」として付く。裏のままだと画面外の遅延読み込みが動かず、
# 画像が載らない。専用の headless Chrome なので、表に出しても利用者の画面は変わらない
activate_tab(current_tab())
cands = [os.environ.get("MD_COOKIES") or "",
         os.path.expanduser("~/.config/mdbird/x_cookies.json"),
         os.path.expanduser("~/.config/mdbird/x-cookies.json")]
path = next((p for p in cands if p and os.path.isfile(p)), None)
if not path:
    print("ready no-cookies")
else:
    data = json.load(open(path, encoding="utf-8"))
    out = []
    if isinstance(data, dict):
        # {"auth_token": "...", "ct0": "..."} の形
        for name in ("auth_token", "ct0"):
            if data.get(name):
                out.append({"name": name, "value": data[name], "domain": ".x.com", "path": "/",
                            "secure": True, "httpOnly": name == "auth_token"})
    else:
        # CDP / ブラウザ拡張で書き出したクッキーの配列
        for c in data:
            d = {k: c[k] for k in ("name", "value", "domain", "path", "secure", "httpOnly") if k in c}
            if isinstance(c.get("expires"), (int, float)) and c["expires"] > 0:
                d["expires"] = c["expires"]
            if c.get("sameSite") in ("Strict", "Lax", "None"):
                d["sameSite"] = c["sameSite"]
            out.append(d)
    if out:
        cdp("Network.setCookies", cookies=out)
    print("ready cookies=%d" % len(out))
PY
}

open_url(){
  load_state "$1"
  MD_URL="$2" bu <<'PY' | tail -1
import os
# goto_url は Page.navigate を 5 秒の待ちで呼び、x.com だと切れることがある。待ちを延ばして直接呼ぶ
cdp("Page.navigate", url=os.environ["MD_URL"], _response_timeout=30)
wait_for_load(timeout=30)
print(js("location.href"))
PY
}

run_js(){
  local code
  load_state "$1"
  if [ $# -ge 2 ] && [ "$2" != "-" ]; then code=$2; else code=$(cat); fi
  MD_JS="$code" bu <<'PY'
import os, json
r = js(os.environ["MD_JS"])
print(r if isinstance(r, str) else json.dumps(r, ensure_ascii=False))
PY
}

scroll(){
  load_state "$1"
  bu <<'PY' | tail -1
import time
# 高さが伸びなくなるまで下端へ送り、遅延読み込みを出し切ってから上へ戻る
prev, same = -1, 0
for _ in range(20):
    h = js("window.scrollTo(0, document.body.scrollHeight); document.body.scrollHeight")
    same = same + 1 if h == prev else 0
    prev = h
    if same >= 2:
        break
    time.sleep(1.5)
js("window.scrollTo(0, 0)")
print("height=%s" % prev)
PY
}

screenshot(){
  load_state "$1"
  mkdir -p "$(dirname "$2")"
  MD_PATH="$2" bu <<'PY' | tail -1
import os
print(capture_screenshot(os.environ["MD_PATH"]))
PY
}

stop(){
  local s=$1 f; f=$(state_file "$s")
  [ -f "$f" ] || { echo "stopped"; return 0; }
  load_state "$s"
  browser-use --reload >/dev/null 2>&1   # このセッションのデーモンだけを止める
  # Chrome の PID だけ止めても子のプロセスが残る。プロセスグループごと止める
  # （名前で探して止める方法は、呼び出し元のシェルにも当たるので使わない）
  if [ -n "${PID:-}" ]; then
    kill -- "-$PID" 2>/dev/null
    for _ in $(seq 1 20); do kill -0 "$PID" 2>/dev/null || break; sleep 0.25; done
    kill -KILL -- "-$PID" 2>/dev/null
  fi
  # 止めた直後は子のプロセスがまだ書いていて消し損ねることがあるので、数回試す
  for _ in 1 2 3 4 5; do rm -rf "$PROFILE" 2>/dev/null; [ -d "$PROFILE" ] || break; sleep 0.5; done
  rm -f "$f" "$HOME/.config/browser-harness/runtime/bu-$BU_NAME."* "$HOME/.config/browser-harness/tmp/bu-$BU_NAME."*
  echo "stopped"
}

# start が裏で走らせる保険。同じ Chrome がまだ動いていれば止める
expire(){
  local s=$1 pid=$2 life=$3 f
  sleep "$life"
  f=$(state_file "$s")
  [ -f "$f" ] && grep -qx "PID=$pid" "$f" && stop "$s" >/dev/null 2>&1
}

cmd=${1:-}; shift || true
case "$cmd" in
  check)      check ;;
  start)      valid_session "${1:-}"; start "$1" ;;
  open)       valid_session "${1:-}"; [ -n "${2:-}" ] || die "URL が要る"; open_url "$1" "$2" ;;
  js)         valid_session "${1:-}"; run_js "$@" ;;
  scroll)     valid_session "${1:-}"; scroll "$1" ;;
  screenshot) valid_session "${1:-}"; [ -n "${2:-}" ] || die "保存先が要る"; screenshot "$1" "$2" ;;
  stop)       valid_session "${1:-}"; stop "$1" ;;
  _expire)    expire "$@" ;;
  *) sed -n '2,25p' "$0" >&2; exit 2 ;;
esac
