#!/bin/bash
# =============================================================================
# audit-log.sh — 操作紀錄腳本 v1.1
# 用途：記錄所有部署相關操作
# 使用方式：
#   source audit-log.sh
#   audit_log [動作] [專案] [結果] [說明]
# 或直接執行：
#   bash audit-log.sh [動作] [專案] [結果] [說明]
# 寫入失敗或參數不合法時回傳非零，呼叫端不可當作已記錄。
# =============================================================================

AUDIT_LOG_DIR="${AUDIT_LOG_DIR:-/opt/apps}"

_audit_json_esc() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    s=${s//[[:cntrl:]]/}
    printf '%s' "$s"
}

audit_log() {
    local ACTION="${1:-}"
    local PROJECT="${2:-}"
    local RESULT="${3:-}"
    local MESSAGE="${4:-}"

    if [ -z "$ACTION" ] || [ -z "$PROJECT" ] || [ -z "$RESULT" ]; then
        echo "❌ Audit 未記錄：動作、專案、結果皆為必填" >&2
        return 1
    fi
    if [[ ! "$PROJECT" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        echo "❌ Audit 未記錄：專案名稱不合法：$PROJECT" >&2
        return 1
    fi
    if [ ! -d "$AUDIT_LOG_DIR/$PROJECT" ]; then
        echo "❌ Audit 未記錄：找不到專案目錄 $AUDIT_LOG_DIR/$PROJECT" >&2
        return 1
    fi

    local LOG_FILE="$AUDIT_LOG_DIR/$PROJECT/logs/audit.log"
    local ENTRY
    ENTRY=$(printf '{"timestamp":"%s","action":"%s","project":"%s","user":"%s","result":"%s","message":"%s"}' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "$(_audit_json_esc "$ACTION")" \
        "$(_audit_json_esc "$PROJECT")" \
        "$(_audit_json_esc "$(whoami)")" \
        "$(_audit_json_esc "$RESULT")" \
        "$(_audit_json_esc "$MESSAGE")")

    if ! { mkdir -p "$(dirname "$LOG_FILE")" && echo "$ENTRY" >> "$LOG_FILE"; } 2>/dev/null; then
        echo "❌ Audit 寫入失敗：$LOG_FILE" >&2
        return 1
    fi
    echo "📋 Audit: [$RESULT] $ACTION — $PROJECT ${MESSAGE:+| $MESSAGE}"
}

# 如果直接執行（非 source）
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if [ $# -lt 3 ]; then
        echo "使用方式：bash audit-log.sh [動作] [專案] [結果] [說明（選填）]" >&2
        exit 1
    fi
    audit_log "$1" "$2" "$3" "${4:-}"
fi
