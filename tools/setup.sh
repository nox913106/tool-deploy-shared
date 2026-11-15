#!/bin/bash
# =============================================================================
# setup.sh — 環境統一化腳本 v1.1
# 用途：在目標主機上建立標準化部署環境
# 使用方式：bash setup.sh [專案名稱]
# 必須在人工確認 project-context.md 後才能執行
# =============================================================================

set -euo pipefail

PROJECT_NAME="${1:-}"
if [ -z "$PROJECT_NAME" ]; then
    echo "❌ 請提供專案名稱：bash setup.sh [專案名稱]"
    exit 1
fi

if [[ ! "$PROJECT_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "❌ 專案名稱不合法：$PROJECT_NAME"
    echo "   只能使用英數字、. _ -，且不可包含路徑"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/audit-log.sh"

PROJECT_DIR="/opt/apps/$PROJECT_NAME"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "=== setup.sh 開始執行 ==="
echo "專案名稱：$PROJECT_NAME"
echo "目標目錄：$PROJECT_DIR"
echo "時間：$TIMESTAMP"
echo ""

# 人工確認
echo "⚠️  即將建立部署環境，請確認以下資訊："
echo "   專案名稱：$PROJECT_NAME"
echo "   目標目錄：$PROJECT_DIR"
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
        audit_log "setup" "$PROJECT_NAME" "fail" "exit code $rc" || true
    fi
}
trap on_exit EXIT

# 建立目錄結構
echo ""
echo "▶ 建立目錄結構..."
mkdir -p "$PROJECT_DIR"/{src,config,logs,venv,rollback}
echo "✅ 目錄結構建立完成"

# 建立 Python 虛擬環境
echo ""
echo "▶ 建立 Python 虛擬環境..."
if [ ! -d "$PROJECT_DIR/venv" ] || [ ! -f "$PROJECT_DIR/venv/bin/activate" ]; then
    python3 -m venv "$PROJECT_DIR/venv"
    echo "✅ 虛擬環境建立完成"
else
    echo "ℹ️  虛擬環境已存在，跳過"
fi

# 建立 log 檔案
echo ""
echo "▶ 建立 log 檔案..."
touch "$PROJECT_DIR/logs/app.log"
touch "$PROJECT_DIR/logs/audit.log"
echo "✅ Log 檔案建立完成"

# 建立 claude-progress.txt 範本
if [ ! -f "$PROJECT_DIR/claude-progress.txt" ]; then
    cat > "$PROJECT_DIR/claude-progress.txt" << EOF
# claude-progress.txt

最後更新：$TIMESTAMP
目前完成：（尚未開始）
下一步：初始化完成，可以開始開發
已知問題：無
相關 commit：無
EOF
    echo "✅ claude-progress.txt 建立完成"
fi

audit_log "setup" "$PROJECT_NAME" "success" "目錄結構與虛擬環境建立完成"

echo ""
echo "=== setup.sh 完成 ==="
echo "專案目錄：$PROJECT_DIR"
echo "請執行 source $PROJECT_DIR/venv/bin/activate 啟用虛擬環境"
