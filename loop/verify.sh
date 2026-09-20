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

: "${PROJECT_NAME:?loop.conf 缺少 PROJECT_NAME}"
: "${SERVICE_PORT:?loop.conf 缺少 SERVICE_PORT}"

HEALTH_URL="http://127.0.0.1:${SERVICE_PORT}/api/v1/health"

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
if command -v ruff >/dev/null 2>&1; then
    if ! g1_out=$(ruff check . --quiet 2>&1); then g1_ok=0; fi
else
    g1_out="ruff 未安裝"; g1_ok=0
fi
if [[ $g1_ok -eq 1 ]] && command -v black >/dev/null 2>&1; then
    if ! b_out=$(black --check . --quiet 2>&1); then
        g1_ok=0; g1_out="$b_out"
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
        record "G2-單元測試" "FAIL" "$(echo "$t_out" | grep -E '^(FAILED|E ) ' | head -3 | tr '\n' ' ')"
    fi
else
    record "G2-單元測試" "FAIL" "pytest 未安裝"
fi

# ── G3 服務存活 ─────────────────────────────────────────────
if systemctl list-unit-files 2>/dev/null | grep -q "^${PROJECT_NAME}.service"; then
    s_state=$(systemctl is-active "${PROJECT_NAME}" 2>&1)
    if [[ "$s_state" == "active" ]]; then
        record "G3-服務存活" "PASS" "systemd active"
    else
        s_log=$(journalctl -u "${PROJECT_NAME}" -n 5 --no-pager 2>/dev/null | tr '\n' ' ')
        record "G3-服務存活" "FAIL" "state=${s_state} :: ${s_log}"
    fi
else
    record "G3-服務存活" "SKIP" "service 尚未安裝（開發階段正常）"
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
PATTERNS='cdn\.|cdnjs|unpkg|jsdelivr|fonts\.googleapis|fonts\.gstatic|https?://'
IGNORE_FILE="${PROJECT_DIR}/.verifyignore"
g5_hits=""
for d in templates static; do
    [[ -d "$d" ]] || continue
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ -f "$IGNORE_FILE" ]]; then
            f_path="${line%%:*}"
            grep -Fxq "$f_path" "$IGNORE_FILE" 2>/dev/null && continue
        fi
        g5_hits+="${line}"$'\n'
    done < <(grep -rInE "$PATTERNS" "$d" 2>/dev/null | grep -v '^\s*$')
done
if [[ -z "$g5_hits" ]]; then
    record "G5-前端資源落地" "PASS" "無外部資源引用"
else
    n=$(echo "$g5_hits" | grep -c . )
    record "G5-前端資源落地" "FAIL" "${n} 筆外部引用 :: $(echo "$g5_hits" | head -3 | cut -c1-90 | tr '\n' ' ')"
fi

# ── G6 安全基準 ─────────────────────────────────────────────
g6_hits=""
# 硬編碼憑證
g6_hits+=$(grep -rInE '(password|passwd|secret|token|api_?key)[[:space:]]*=[[:space:]]*["'"'"'][^"'"'"']{6,}' \
    --include='*.py' --include='*.js' --include='*.html' . 2>/dev/null \
    | grep -viE '(getenv|environ|settings\.|config\.|example|placeholder|\{\{|\$\{)' | head -5)
# 危險刪除
g6_hits+=$'\n'$(grep -rInE 'rm[[:space:]]+-[rf]{1,2}f?[[:space:]]' \
    --include='*.py' --include='*.sh' . 2>/dev/null | head -5)
# shell injection
g6_hits+=$'\n'$(grep -rIn 'shell[[:space:]]*=[[:space:]]*True' --include='*.py' . 2>/dev/null | head -5)
# .env 被追蹤
if git -C "$PROJECT_DIR" ls-files --error-unmatch .env >/dev/null 2>&1; then
    g6_hits+=$'\n'".env 被 git 追蹤（嚴重）"
fi
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
