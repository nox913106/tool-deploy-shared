#!/bin/bash
# =============================================================================
# rollback.sh — 回復腳本 v1.1
# 用途：將部署回復到上一個版本
# 使用方式：bash rollback.sh [專案名稱] [版本目錄（選填）]
# =============================================================================

set -euo pipefail

PROJECT_NAME="${1:-}"
TARGET_VERSION="${2:-}"

if [ -z "$PROJECT_NAME" ]; then
    echo "❌ 請提供專案名稱：bash rollback.sh [專案名稱]"
    exit 1
fi

NAME_RE='^[A-Za-z0-9][A-Za-z0-9._-]*$'
if [[ ! "$PROJECT_NAME" =~ $NAME_RE ]]; then
    echo "❌ 專案名稱不合法：$PROJECT_NAME"
    exit 1
fi
if [ -n "$TARGET_VERSION" ] && [[ ! "$TARGET_VERSION" =~ $NAME_RE ]]; then
    echo "❌ 版本名稱不合法：$TARGET_VERSION（只能是 rollback/ 下的目錄名稱，不可包含路徑）"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/audit-log.sh"

PROJECT_DIR="/opt/apps/$PROJECT_NAME"
ROLLBACK_DIR="$PROJECT_DIR/rollback"

if [ ! -d "$ROLLBACK_DIR" ]; then
    echo "❌ 找不到 rollback 目錄：$ROLLBACK_DIR"
    exit 1
fi

echo "=== rollback.sh 開始執行 ==="
echo "專案名稱：$PROJECT_NAME"
echo ""

# 列出可用版本（依目錄名稱的時間戳排序，新的在前；不看 mtime）
VERSIONS=$(find "$ROLLBACK_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r)
echo "可用的備份版本："
if [ -n "$VERSIONS" ]; then
    echo "$VERSIONS"
else
    echo "  （無備份）"
fi
echo ""

# 選擇版本：未指定時取時間戳最新的 YYYYMMDD-HHMMSS
if [ -z "$TARGET_VERSION" ]; then
    LATEST=$(echo "$VERSIONS" | grep -E '^[0-9]{8}-[0-9]{6}$' | sort -r | sed -n '1p' || true)
    if [ -z "$LATEST" ]; then
        echo "❌ 沒有可用的備份版本（請先執行 backup.sh）"
        exit 1
    fi
    echo "將回復到最新備份：$LATEST"
    TARGET_VERSION="$LATEST"
fi

TARGET_PATH="$ROLLBACK_DIR/$TARGET_VERSION"
if [ ! -d "$TARGET_PATH/src" ]; then
    echo "❌ 找不到版本，或該版本沒有 src/：$TARGET_VERSION"
    exit 1
fi
if ! command -v rsync >/dev/null 2>&1; then
    echo "❌ 缺少必要工具：rsync"
    exit 1
fi

# 人工確認
echo ""
echo "⚠️  即將執行回復，請確認："
echo "   回復目標：$TARGET_PATH"
echo "   執行帳號：$(whoami)"
echo ""
if ! read -rp "確認繼續？(yes/no): " CONFIRM; then
    echo ""
    echo "❌ 無法讀取確認輸入（需在互動式終端機執行）"
    exit 1
fi
if [ "$CONFIRM" != "yes" ]; then
    echo "❌ 已取消"
    exit 0
fi

# 確認之後的任何失敗都要留下稽核紀錄
on_exit() {
    local rc=$?
    if [ $rc -ne 0 ]; then
        audit_log "rollback" "$PROJECT_NAME" "fail" "version=$TARGET_VERSION, exit code $rc" || true
    fi
}
trap on_exit EXIT

# 執行回復
echo ""
echo "▶ 執行回復..."
rsync -a --delete "$TARGET_PATH/src/" "$PROJECT_DIR/src/"
echo "✅ 程式碼回復完成"

# 記錄 audit log
audit_log "rollback" "$PROJECT_NAME" "success" "version=$TARGET_VERSION"

echo ""
echo "=== rollback.sh 完成 ==="
echo "已回復至版本：$TARGET_VERSION"
echo "請重新啟動服務並驗證運行狀態"
