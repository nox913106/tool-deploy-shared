#!/bin/bash
# =============================================================================
# verify.sh — 自動驗證器
# -----------------------------------------------------------------------------
# Loop Engineering 的核心：驗證器是瓶頸，不是模型。
# 這支腳本回答一個問題：「現在這個狀態，算不算完成？」
#
# 輸出：
#   - 人類可讀的 gate 結果（stdout）
#   - 機器可讀的 JSON（--json）供 loop.sh 解析
# 退出碼：
#   0  = 全部通過
#   1  = 有 gate 失敗（可重試）
#   2  = 設定錯誤或環境缺失（不可重試，需人工）
# =============================================================================

set -uo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
CONF="${PROJECT_DIR}/loop.conf"
JSON_MODE=0
[[ "${1:-}" == "--json" ]] && JSON_MODE=1

# ── 載入設定 ────────────────────────────────────────────────
if [[ ! -f "$CONF" ]]; then
    echo "ERROR: 找不到 loop.conf，無法驗證" >&2
    exit 2
fi
# shellcheck source=/dev/null
source "$CONF"

for v in PROJECT_NAME SERVICE_PORT; do
    if [[ -z "${!v:-}" ]]; then
        echo "ERROR: loop.conf 缺少 ${v}" >&2
        exit 2
    fi
done

# 1 = service 未安裝視為失敗（預設，對應 DONE.md G3）；0 = 開發階段，略過
REQUIRE_SERVICE="${REQUIRE_SERVICE:-1}"

BASE_URL="http://127.0.0.1:${SERVICE_PORT}"
HEALTH_URL="${BASE_URL}/api/v1/health"

# 掃描時一律略過的目錄（第三方套件、快取、迴圈自己的狀態）
EXCLUDE_DIRS=(.git .loop venv .venv node_modules __pycache__ .pytest_cache .ruff_cache .mypy_cache site-packages)
GREP_EXCL=()
for d in "${EXCLUDE_DIRS[@]}"; do GREP_EXCL+=(--exclude-dir="$d"); done
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 結果收集 ────────────────────────────────────────────────
declare -a GATE_NAMES=()
declare -a GATE_STATUS=()
declare -a GATE_DETAIL=()
FAILED=0

record() {
    GATE_NAMES+=("$1")
    GATE_STATUS+=("$2")
    GATE_DETAIL+=("$3")
    [[ "$2" == "FAIL" ]] && FAILED=1
    if [[ $JSON_MODE -eq 0 ]]; then
        local icon="✓"
        [[ "$2" == "FAIL" ]] && icon="✗"
        [[ "$2" == "SKIP" ]] && icon="—"
        printf "  %s %-22s %s\n" "$icon" "$1" "$3"
    fi
}

[[ $JSON_MODE -eq 0 ]] && echo "── verify.sh :: ${PROJECT_NAME} ──"

cd "$PROJECT_DIR" || exit 2

# ── G1 靜態檢查 ─────────────────────────────────────────────
g1_out=""
g1_ok=1
if ! command -v ruff >/dev/null 2>&1; then
    g1_out="ruff 未安裝"; g1_ok=0
elif ! g1_out=$(ruff check . --quiet 2>&1); then
    g1_ok=0
fi
if [[ $g1_ok -eq 1 ]]; then
    if ! command -v black >/dev/null 2>&1; then
        g1_out="black 未安裝"; g1_ok=0
    elif ! b_out=$(black --check . 2>&1); then
        g1_ok=0
        g1_out=$(echo "$b_out" | grep -E '^(would reformat|error)')
        [[ -z "$g1_out" ]] && g1_out="$b_out"
    fi
fi
if [[ $g1_ok -eq 1 ]]; then
    record "G1-靜態檢查" "PASS" "ruff + black 通過"
else
    record "G1-靜態檢查" "FAIL" "$(echo "$g1_out" | head -5 | tr '\n' ' ')"
fi

# ── G2 單元測試 ─────────────────────────────────────────────
if command -v pytest >/dev/null 2>&1; then
    t_out=$(pytest -q --tb=short 2>&1)
    t_rc=$?
    t_count=$(echo "$t_out" | grep -oE '[0-9]+ (passed|failed)' | head -1 | grep -oE '^[0-9]+')
    if [[ $t_rc -eq 0 && -n "${t_count:-}" && "${t_count:-0}" -gt 0 ]]; then
        record "G2-單元測試" "PASS" "${t_count} 個測試通過"
    elif [[ $t_rc -eq 0 ]]; then
        record "G2-單元測試" "FAIL" "測試數量為 0，空測試不算通過"
    else
        t_detail=$(echo "$t_out" | grep -E '^(FAILED|ERROR|E ) ' | head -3 | tr '\n' ' ')
        [[ $t_rc -eq 5 ]] && t_detail="未收集到任何測試（pytest exit 5），空測試不算通過"
        [[ -z "${t_detail// /}" ]] && t_detail="pytest exit ${t_rc} :: $(echo "$t_out" | tail -3 | tr '\n' ' ')"
        record "G2-單元測試" "FAIL" "$t_detail"
    fi
else
    record "G2-單元測試" "FAIL" "pytest 未安裝"
fi

# ── G3 服務存活 ─────────────────────────────────────────────
unit_found=0
while read -r unit _; do
    [[ "$unit" == "${PROJECT_NAME}.service" ]] && unit_found=1
done < <(systemctl list-unit-files 2>/dev/null)
if [[ $unit_found -eq 1 ]]; then
    s_state=$(systemctl is-active "${PROJECT_NAME}" 2>&1)
    if [[ "$s_state" == "active" ]]; then
        record "G3-服務存活" "PASS" "systemd active"
    else
        s_log=$(journalctl -u "${PROJECT_NAME}" -n 5 --no-pager 2>/dev/null | tr '\n' ' ')
        record "G3-服務存活" "FAIL" "state=${s_state} :: ${s_log}"
    fi
elif [[ "$REQUIRE_SERVICE" == "0" ]]; then
    record "G3-服務存活" "SKIP" "service 尚未安裝（REQUIRE_SERVICE=0，開發階段）"
else
    record "G3-服務存活" "FAIL" "service 未安裝（開發階段可在 loop.conf 設 REQUIRE_SERVICE=0）"
fi

# ── G4 健康端點 ─────────────────────────────────────────────
h_out=$(curl -fsS --max-time 5 "$HEALTH_URL" 2>&1)
h_rc=$?
if [[ $h_rc -eq 0 ]] && echo "$h_out" | grep -q '"status"[[:space:]]*:[[:space:]]*"ok"'; then
    record "G4-健康端點" "PASS" "200 OK, status=ok"
elif [[ $h_rc -eq 0 ]]; then
    record "G4-健康端點" "FAIL" "有回應但 status 非 ok: ${h_out:0:120}"
else
    record "G4-健康端點" "FAIL" "無法連線 ${HEALTH_URL} :: ${h_out:0:120}"
fi

# ── G5 前端資源落地 ─────────────────────────────────────────
# 這條直接對應 SYSTEM_STANDARD.md 的「不依賴外部資源」原則。
# UI/UX 要好看，但不能用 CDN 換來的好看。
# 掃描專案內所有名為 templates/ 或 static/ 的目錄（含 app/ 之下）。
#
# .verifyignore 每行一筆例外（# 開頭為註解）：
#   path/to/file            整個檔案不檢查
#   path/to/file: 字串      只放行該檔案中「含有這段字串」的那幾行
PATTERNS='cdn\.|cdnjs|unpkg|jsdelivr|fonts\.googleapis|fonts\.gstatic|https?://'
IGNORE_FILE="${PROJECT_DIR}/.verifyignore"

is_ignored() {
    [[ -f "$IGNORE_FILE" ]] || return 1
    local entry
    while IFS= read -r entry || [[ -n "$entry" ]]; do
        [[ -z "$entry" || "$entry" == \#* ]] && continue
        if [[ "$entry" == *": "* ]]; then
            [[ "$1" == "${entry%%: *}" && "$2" == *"${entry#*: }"* ]] && return 0
        else
            [[ "$1" == "$entry" ]] && return 0
        fi
    done < "$IGNORE_FILE"
    return 1
}

g5_prune=()
for d in "${EXCLUDE_DIRS[@]}"; do g5_prune+=(-name "$d" -o); done
g5_hits=""
while IFS= read -r d; do
    d="${d#./}"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        f_path="${line%%:*}"
        content="${line#*:}"; content="${content#*:}"
        is_ignored "$f_path" "$content" && continue
        # XML 命名空間與 DOCTYPE 只是識別字串，瀏覽器不會去抓
        cleaned=$(sed -E "s/xmlns(:[A-Za-z0-9_-]+)?=(\"[^\"]*\"|'[^']*')//g; s/<!DOCTYPE[^>]*>//Ig" <<<"$content")
        grep -qE "$PATTERNS" <<<"$cleaned" || continue
        g5_hits+="${line}"$'\n'
    done < <(grep -rInE "$PATTERNS" "$d" 2>/dev/null)
done < <(find . \( "${g5_prune[@]}" -false \) -prune -o \
    -type d \( -name templates -o -name static \) -print -prune 2>/dev/null | sort)
if [[ -z "$g5_hits" ]]; then
    record "G5-前端資源落地" "PASS" "無外部資源引用"
else
    n=$(echo "$g5_hits" | grep -c . )
    record "G5-前端資源落地" "FAIL" "${n} 筆外部引用 :: $(echo "$g5_hits" | head -3 | cut -c1-90 | tr '\n' ' ')"
fi

# ── G6 安全基準 ─────────────────────────────────────────────
g6_hits=""
# 迴圈自己的腳本含有掃描用的樣式字串，不列入掃描
g6_self() {
    if [[ "$HERE" == "$PROJECT_DIR" ]]; then grep -vE '^\./(loop|verify)\.sh:'; else cat; fi
}
G6_CODE=(--include='*.py' --include='*.js' --include='*.ts' --include='*.html' --include='*.sh')
G6_CONF=(--include='*.yaml' --include='*.yml' --include='*.ini' --include='*.cfg' --include='*.toml')
# 只比對內容，不比對檔名（否則 settings.py、config.yaml 整個檔案都會被放行）
G6_NOT_SECRET='^[^:]*:[0-9]+:.*(getenv|environ|settings\.|config\.|example|placeholder|\{\{|\$\{)'
# 硬編碼憑證：鍵名以這些字結尾（不分大小寫），用 = 或 : 指定字串值
# tests/ 內的假資料不列入
KEYS='(password|passwd|secret|secret_?key|token|api_?key|access_?key|private_?key)'
TYPE_HINT='(:[[:space:]]*[A-Za-z_][A-Za-z0-9_.| ]*)?'
g6_hits+=$(grep -rIniE "${KEYS}[\"']?[[:space:]]*${TYPE_HINT}[[:space:]]*[:=][[:space:]]*[\"'][^\"']{6,}" \
    "${G6_CODE[@]}" "${G6_CONF[@]}" "${GREP_EXCL[@]}" --exclude-dir=tests . 2>/dev/null \
    | g6_self | grep -viE "$G6_NOT_SECRET" | head -5)
# 設定檔中未加引號的值
g6_hits+=$'\n'$(grep -rIniE "${KEYS}[[:space:]]*[:=][[:space:]]*[^][:space:]\"'#\$<{[][^[:space:]]{5,}" \
    "${G6_CONF[@]}" "${GREP_EXCL[@]}" --exclude-dir=tests . 2>/dev/null \
    | grep -viE "$G6_NOT_SECRET" | head -5)
# 危險刪除：rm 帶 -r / -R / -f（任何組合、長選項）與 shutil.rmtree
g6_hits+=$'\n'$(grep -rInE "(^|[^[:alnum:]_./-])rm[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(-[a-zA-Z]*[rRf][a-zA-Z]*|--recursive|--force)([^[:alnum:]-]|\$)" \
    --include='*.py' --include='*.sh' "${GREP_EXCL[@]}" . 2>/dev/null | g6_self | head -5)
g6_hits+=$'\n'$(grep -rInE 'shutil\.rmtree[[:space:]]*\(' --include='*.py' "${GREP_EXCL[@]}" . 2>/dev/null | head -5)
# shell injection
g6_hits+=$'\n'$(grep -rIn 'shell[[:space:]]*=[[:space:]]*True' --include='*.py' "${GREP_EXCL[@]}" . 2>/dev/null | head -5)
# .env 被追蹤
if git -C "$PROJECT_DIR" ls-files --error-unmatch .env >/dev/null 2>&1; then
    g6_hits+=$'\n'".env 被 git 追蹤（嚴重）"
fi
# /docs 與 /redoc 必須關閉：直接問運行中的服務（連不上時由 G4 負責回報）
for ep in /docs /redoc; do
    ep_code=$(curl -s -o /dev/null --max-time 5 -w '%{http_code}' "${BASE_URL}${ep}" 2>/dev/null)
    if [[ "$ep_code" == "200" ]]; then
        g6_hits+=$'\n'"${ep} 可存取（HTTP 200），生產環境必須關閉"
    fi
done
g6_clean=$(echo "$g6_hits" | grep -c . )
if [[ "$g6_clean" -eq 0 ]]; then
    record "G6-安全基準" "PASS" "無違規"
else
    record "G6-安全基準" "FAIL" "${g6_clean} 筆 :: $(echo "$g6_hits" | grep . | head -3 | cut -c1-90 | tr '\n' ' ')"
fi

# ── 輸出 ────────────────────────────────────────────────────
if [[ $JSON_MODE -eq 1 ]]; then
    printf '{"project":"%s","passed":%s,"gates":[' \
        "$PROJECT_NAME" "$([[ $FAILED -eq 0 ]] && echo true || echo false)"
    for i in "${!GATE_NAMES[@]}"; do
        [[ $i -gt 0 ]] && printf ','
        d=${GATE_DETAIL[$i]//\"/\'}
        d=${d//\\/}
        d=${d//[[:cntrl:]]/ }
        printf '{"gate":"%s","status":"%s","detail":"%s"}' \
            "${GATE_NAMES[$i]}" "${GATE_STATUS[$i]}" "$d"
    done
    printf ']}\n'
else
    echo "──"
    if [[ $FAILED -eq 0 ]]; then
        echo "  結果：全部通過 ✓"
    else
        echo "  結果：有 gate 失敗 ✗"
    fi
fi

exit $FAILED
