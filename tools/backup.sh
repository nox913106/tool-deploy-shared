#!/bin/bash
# =============================================================================
# backup.sh — 部署前備份腳本 v1.0
# 用途：依 DEPLOY_STANDARD 第 6 節，在部署前備份目前版本供 rollback.sh 使用
# 使用方式：bash backup.sh [專案名稱]
# 產出：/opt/apps/{專案}/rollback/YYYYMMDD-HHMMSS/
#         ├── src/                          現有程式碼
#         ├── requirements-snapshot.txt     venv 套件清單
#         └── service-status-snapshot.txt   服務狀態
# 本腳本只新增檔案，不刪除任何東西。
# =============================================================================

set -euo pipefail

KEEP=3
PROJECT_NAME="${1:-}"
if [ -z "$PROJECT_NAME" ]; then
    echo "❌ 請提供專案名稱：bash backup.sh [專案名稱]"
    exit 1
fi
if [[ ! "$PROJECT_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "❌ 專案名稱不合法：$PROJECT_NAME"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/audit-log.sh"

PROJECT_DIR="/opt/apps/$PROJECT_NAME"
ROLLBACK_DIR="$PROJECT_DIR/rollback"

if [ ! -d "$PROJECT_DIR/src" ] || [ ! -d "$ROLLBACK_DIR" ]; then
    echo "❌ 找不到 $PROJECT_DIR/src 或 $ROLLBACK_DIR（請先執行 setup.sh）"
    exit 1
fi

VERSION=$(date '+%Y%m%d-%H%M%S')
DEST="$ROLLBACK_DIR/$VERSION"
if [ -e "$DEST" ]; then
    echo "❌ 備份版本已存在：$DEST（請稍後再試）"
    exit 1
fi

echo "=== backup.sh 開始執行 ==="
echo "專案名稱：$PROJECT_NAME"
echo "備份版本：$VERSION"
echo ""

on_exit() {
    local rc=$?
    if [ $rc -ne 0 ]; then
        audit_log "backup" "$PROJECT_NAME" "fail" "version=$VERSION, exit code $rc" || true
    fi
}
trap on_exit EXIT

echo "▶ 備份程式碼..."
mkdir -p "$DEST/src"
cp -a "$PROJECT_DIR/src/." "$DEST/src/"
echo "✅ 程式碼備份完成"

echo "▶ 記錄 venv 套件清單..."
if [ -x "$PROJECT_DIR/venv/bin/pip" ]; then
    "$PROJECT_DIR/venv/bin/pip" freeze > "$DEST/requirements-snapshot.txt"
    echo "✅ requirements-snapshot.txt 完成"
else
    echo "（找不到 venv，未記錄套件清單）" > "$DEST/requirements-snapshot.txt"
    echo "⚠️  找不到 $PROJECT_DIR/venv/bin/pip，套件清單未記錄"
fi

echo "▶ 記錄服務狀態..."
{
    echo "# 記錄時間：$(date '+%Y-%m-%d %H:%M:%S')"
    echo "# $PROJECT_NAME: $(systemctl is-active "$PROJECT_NAME" 2>/dev/null || true)"
    echo ""
    systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null \
        || echo "（無法查詢 systemd 服務狀態）"
} > "$DEST/service-status-snapshot.txt"
echo "✅ service-status-snapshot.txt 完成"

audit_log "backup" "$PROJECT_NAME" "success" "version=$VERSION"

# 保留最近 KEEP 個版本：本腳本不刪除檔案，超出的版本列出交由人工處理
OLD=$(find "$ROLLBACK_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
    | grep -E '^[0-9]{8}-[0-9]{6}$' | sort -r | sed "1,${KEEP}d" || true)
if [ -n "$OLD" ]; then
    echo ""
    echo "⚠️  備份已超過 $KEEP 個版本，以下舊版本請人工確認後清理："
    echo "$OLD" | sed "s|^|   $ROLLBACK_DIR/|"
fi

echo ""
echo "=== backup.sh 完成 ==="
echo "回復方式：bash rollback.sh $PROJECT_NAME $VERSION"
