#!/bin/bash
# =============================================================================
# loop.sh — 迴圈控制器
# -----------------------------------------------------------------------------
# 「你不再 prompt agent，你設計一個系統來 prompt agent。」
#
# 這支腳本是你的 harness 從「手動線性流程」升級為「自動迴圈」的那一層。
# 它不取代 CLAUDE.md（規則層）和 deploy-guard（安全層）——
# 那兩層是護欄，這一層是軌道。
#
# 用法：
#   ./loop.sh "把設備清單頁面加上依機房篩選的功能"
#   ./loop.sh --resume          # 接續上次未完成的 run
#   ./loop.sh --status          # 查看歷史
#   ./loop.sh --dry-run "..."   # 只跑驗證，不呼叫 AI
# =============================================================================

set -uo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
CONF="${PROJECT_DIR}/loop.conf"
STATE_DB="${PROJECT_DIR}/.loop/state.db"
LOG_DIR="${PROJECT_DIR}/.loop/logs"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 前置檢查：沒有 DONE.md 就不准跑 ──────────────────────────
if [[ ! -f "${PROJECT_DIR}/DONE.md" ]]; then
    echo "✗ 找不到 DONE.md。"
    echo "  迴圈的前提是「完成條件必須先被定義」。"
    echo "  沒有 DONE.md 就開跑，只是讓 AI 無限做工而已。"
    exit 2
fi
if [[ ! -f "$CONF" ]]; then
    echo "✗ 找不到 loop.conf"; exit 2
fi
# shellcheck source=/dev/null
source "$CONF"

MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"
TIMEOUT_SEC="${TIMEOUT_SEC:-900}"
AGENT_CMD="${AGENT_CMD:-claude -p}"
PROTECTED="${PROTECTED_PATHS:-docs/ prompts/ .env DONE.md loop.conf}"

mkdir -p "$(dirname "$STATE_DB")" "$LOG_DIR"

# ── 狀態儲存（SQLite，取代人工維護的文字檔）──────────────────
init_db() {
    sqlite3 "$STATE_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS runs (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    goal        TEXT    NOT NULL,
    status      TEXT    NOT NULL DEFAULT 'running',
    started_at  TEXT    NOT NULL,
    ended_at    TEXT,
    attempts    INTEGER DEFAULT 0,
    exit_reason TEXT
);
CREATE TABLE IF NOT EXISTS attempts (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id      INTEGER NOT NULL,
    seq         INTEGER NOT NULL,
    verify_json TEXT,
    passed      INTEGER,
    err_digest  TEXT,
    created_at  TEXT    NOT NULL,
    FOREIGN KEY (run_id) REFERENCES runs(id)
);
CREATE TABLE IF NOT EXISTS tickets (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id      INTEGER,
    severity    TEXT,
    summary     TEXT    NOT NULL,
    status      TEXT    DEFAULT 'open',
    created_at  TEXT    NOT NULL
);
SQL
}

sq() { sqlite3 "$STATE_DB" "$1"; }
now() { date -Iseconds; }
esc() { echo "$1" | sed "s/'/''/g"; }

# ── 子指令 ──────────────────────────────────────────────────
case "${1:-}" in
    --status)
        init_db
        echo "── 最近 10 個 run ──"
        sq "SELECT id, substr(goal,1,42), status, attempts, COALESCE(exit_reason,'') \
            FROM runs ORDER BY id DESC LIMIT 10;" | column -t -s '|'
        echo
        echo "── 未處理的 ticket ──"
        sq "SELECT id, severity, substr(summary,1,60) FROM tickets \
            WHERE status='open' ORDER BY id DESC LIMIT 10;" | column -t -s '|'
        exit 0
        ;;
    --dry-run)
        shift
        echo "── dry-run：只驗證，不呼叫 AI ──"
        bash "${HERE}/verify.sh"
        exit $?
        ;;
esac

init_db

# ── 決定這次的目標 ──────────────────────────────────────────
if [[ "${1:-}" == "--resume" ]]; then
    RUN_ID=$(sq "SELECT id FROM runs WHERE status='running' ORDER BY id DESC LIMIT 1;")
    if [[ -z "$RUN_ID" ]]; then echo "✗ 沒有未完成的 run"; exit 1; fi
    GOAL=$(sq "SELECT goal FROM runs WHERE id=${RUN_ID};")
    START_SEQ=$(( $(sq "SELECT COALESCE(MAX(seq),0) FROM attempts WHERE run_id=${RUN_ID};") + 1 ))
    echo "── 接續 run #${RUN_ID}（從第 ${START_SEQ} 次嘗試）──"
else
    GOAL="${1:-}"
    if [[ -z "$GOAL" ]]; then
        echo "用法：./loop.sh \"你要達成的目標\""
        exit 1
    fi
    sq "INSERT INTO runs (goal, started_at) VALUES ('$(esc "$GOAL")', '$(now)');"
    RUN_ID=$(sq "SELECT last_insert_rowid();")
    START_SEQ=1
fi

echo "════════════════════════════════════════════"
echo " run #${RUN_ID} :: ${GOAL}"
echo " 上限 ${MAX_ATTEMPTS} 次，逾時 ${TIMEOUT_SEC}s"
echo "════════════════════════════════════════════"

# ── 硬性退出：受保護檔案是否被動過 ───────────────────────────
check_protected() {
    local changed
    changed=$(git -C "$PROJECT_DIR" diff --name-only HEAD 2>/dev/null)
    for p in $PROTECTED; do
        if echo "$changed" | grep -q "^${p}"; then
            echo "$p"; return 0
        fi
    done
    return 1
}

finish() {
    local status="$1" reason="$2"
    sq "UPDATE runs SET status='${status}', ended_at='$(now)', \
        attempts=${SEQ:-0}, exit_reason='$(esc "$reason")' WHERE id=${RUN_ID};"
    if [[ "$status" != "passed" ]]; then
        sq "INSERT INTO tickets (run_id, severity, summary, created_at) \
            VALUES (${RUN_ID}, 'high', '$(esc "${reason} :: ${GOAL}")', '$(now)');"
    fi
    echo
    echo "════════════════════════════════════════════"
    echo " run #${RUN_ID} 結束：${status}"
    echo " 原因：${reason}"
    [[ "$status" != "passed" ]] && echo " 已開立 ticket，用 ./loop.sh --status 查看"
    echo "════════════════════════════════════════════"
}

PREV_DIGEST=""
FEEDBACK=""

# ── 主迴圈 ──────────────────────────────────────────────────
for (( SEQ=START_SEQ; SEQ<=MAX_ATTEMPTS; SEQ++ )); do
    echo
    echo "── 第 ${SEQ}/${MAX_ATTEMPTS} 次 ──"
    LOG="${LOG_DIR}/run${RUN_ID}_attempt${SEQ}.log"

    # 組 prompt：目標 + DONE.md + 上一輪的失敗回饋
    PROMPT="目標：${GOAL}

完成條件定義在專案根目錄的 DONE.md，請先讀它。
你必須讓 ./verify.sh 的所有 gate 通過才算完成。

規則：
- 不得修改受保護路徑：${PROTECTED}
- 同一解法最多試 2 次，第 2 次失敗必須換方向
- 換方向前必須先說明「為什麼之前失敗」
- 資訊不足時停止並回報，不得猜測繼續"

    if [[ -n "$FEEDBACK" ]]; then
        PROMPT="${PROMPT}

上一次驗證失敗，以下是 verify.sh 的原始輸出。
請先診斷根本原因，再動手修正：

${FEEDBACK}"
    fi

    # 呼叫 agent
    echo "  → 呼叫 agent…"
    if ! timeout "${TIMEOUT_SEC}" bash -c "cd '${PROJECT_DIR}' && ${AGENT_CMD} \"\$1\"" _ "$PROMPT" >"$LOG" 2>&1; then
        rc=$?
        if [[ $rc -eq 124 ]]; then
            finish "timeout" "第 ${SEQ} 次執行超過 ${TIMEOUT_SEC} 秒"
            exit 3
        fi
        echo "  ⚠ agent 回傳非零（rc=${rc}），仍繼續驗證當前狀態"
    fi

    # 硬性退出：受保護檔案被動
    if violated=$(check_protected); then
        finish "blocked" "受保護檔案被修改：${violated}"
        exit 4
    fi

    # 驗證
    echo "  → 驗證…"
    VJSON=$(bash "${HERE}/verify.sh" --json 2>/dev/null)
    VTEXT=$(bash "${HERE}/verify.sh" 2>&1)
    PASSED=$(echo "$VJSON" | grep -o '"passed":[a-z]*' | cut -d: -f2)
    echo "$VTEXT" | sed 's/^/    /'

    DIGEST=$(echo "$VJSON" | grep -o '"gate":"[^"]*","status":"FAIL"' | sort | md5sum | cut -c1-12)
    sq "INSERT INTO attempts (run_id, seq, verify_json, passed, err_digest, created_at) \
        VALUES (${RUN_ID}, ${SEQ}, '$(esc "$VJSON")', \
        $([[ "$PASSED" == "true" ]] && echo 1 || echo 0), '${DIGEST}', '$(now)');"

    if [[ "$PASSED" == "true" ]]; then
        finish "passed" "所有 gate 通過（第 ${SEQ} 次）"
        echo
        echo "自動部分完成。接下來是只有你能做的事——"
        echo "打開 DONE.md 的「人工驗收」區，檢視 UI/UX。"
        exit 0
    fi

    # 硬性退出：原地打轉
    if [[ -n "$PREV_DIGEST" && "$DIGEST" == "$PREV_DIGEST" ]]; then
        finish "stuck" "連續兩次相同的失敗組合，AI 在原地打轉"
        exit 5
    fi
    PREV_DIGEST="$DIGEST"
    FEEDBACK="$VTEXT"
done

finish "exhausted" "嘗試 ${MAX_ATTEMPTS} 次仍未通過"
exit 6
