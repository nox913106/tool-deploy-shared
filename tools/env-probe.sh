#!/bin/bash
# =============================================================================
# env-probe.sh — 環境探測腳本 v1.1
# 用途：探測目標主機環境，產出 project-context.md
# 使用方式：bash env-probe.sh [專案名稱] [--force]
#   project-context.md 已存在時預設不覆蓋（避免洗掉人工確認）。
#   加 --force 會先把舊檔改名為 project-context.md.YYYYMMDD-HHMMSS.bak 再重新產出。
# 選填環境變數（設定後會實際測試連線）：
#   GITLAB_URL        內網 GitLab 位址
#   PYPI_MIRROR_URL   內部 PyPI mirror 位址
# =============================================================================

set -euo pipefail

PROJECT_NAME="${1:-unknown-project}"
FORCE="${2:-}"
OUTPUT_FILE="project-context.md"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

if [ -e "$OUTPUT_FILE" ]; then
    if [ "$FORCE" != "--force" ]; then
        echo "❌ $OUTPUT_FILE 已存在，為避免覆蓋人工確認內容，未重新產出。"
        echo "   確定要重新探測請加 --force（舊檔會改名保留）。"
        exit 1
    fi
    BACKUP_FILE="$OUTPUT_FILE.$(date '+%Y%m%d-%H%M%S').bak"
    mv "$OUTPUT_FILE" "$BACKUP_FILE"
    echo "ℹ️  舊檔已保留為 $BACKUP_FILE"
fi

echo "=== env-probe.sh 開始執行 ==="
echo "專案名稱：$PROJECT_NAME"
echo "時間：$TIMESTAMP"
echo ""

# 探測函式
probe_os() {
    if [ -f /etc/os-release ]; then
        (source /etc/os-release; echo "${NAME:-unknown} ${VERSION_ID:-}")
    else
        uname -sr
    fi
}

# ── 與 DEPLOY_STANDARD 第 3、5 節比對 ──
check_os() {
    case "$(probe_os)" in
        "Ubuntu 20.04"|"Ubuntu 22.04") echo "- ✅ 作業系統：$(probe_os)" ;;
        *) echo "- ❌ 作業系統：$(probe_os)（標準為 Ubuntu 20.04 LTS 或 22.04 LTS）" ;;
    esac
}

check_python() {
    if ! command -v python3 &>/dev/null; then
        echo "- ❌ Python：未安裝（標準為 3.8+）"
    elif python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
        echo "- ✅ Python：$(python3 --version 2>&1)"
    else
        echo "- ❌ Python：$(python3 --version 2>&1)（標準為 3.8+）"
    fi
    if python3 -c 'import venv, ensurepip' 2>/dev/null; then
        echo "- ✅ venv 模組：可用"
    else
        echo "- ❌ venv 模組：不可用（setup.sh 建立虛擬環境會失敗）"
    fi
}

check_url() {
    local label="$1" url="$2"
    if [ -z "$url" ]; then
        echo "- ⚠️ $label：未設定位址，未測試（請人工確認可達）"
    elif ! command -v curl &>/dev/null; then
        echo "- ⚠️ $label：主機沒有 curl，未測試"
    elif curl -sS -o /dev/null --max-time 5 "$url" 2>/dev/null; then
        echo "- ✅ $label：可達"
    else
        echo "- ❌ $label：無法連線"
    fi
}

probe_containers() {
    if ! command -v docker &>/dev/null; then
        echo "  （未安裝 docker）"
    elif ! out=$(docker ps --format '  - {{.Names}}（{{.Image}}，{{.Status}}）' 2>/dev/null); then
        echo "  （無法查詢：docker 未運行或權限不足）"
    elif [ -z "$out" ]; then
        echo "  （無運行中的 container）"
    else
        echo "$out"
    fi
}

probe_compose() {
    local found
    found=$(find /opt /srv -maxdepth 4 -type f \
        \( -name 'docker-compose*.yml' -o -name 'docker-compose*.yaml' \
           -o -name 'compose.yml' -o -name 'compose.yaml' \) 2>/dev/null | sort | sed 's/^/  - /' || true)
    if [ -n "$found" ]; then echo "$found"; else echo "  （/opt、/srv 下未找到）"; fi
}

probe_python() {
    if command -v python3 &>/dev/null; then
        python3 --version 2>&1
    else
        echo "未安裝"
    fi
}

probe_services() {
    local services=("slapd" "freeradius" "nginx" "apache2" "mysql" "postgresql" "docker")
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo "  - $svc: ✅ 運行中"
        elif systemctl list-unit-files --quiet "$svc.service" 2>/dev/null | grep -q "$svc"; then
            echo "  - $svc: ⚠️ 已安裝但未運行"
        fi
    done
}

probe_disk() {
    df -h /opt 2>/dev/null | tail -1 | awk '{print $4 " 可用 / " $2 " 總計"}'
}

probe_network() {
    ip route 2>/dev/null | grep default | head -1 || echo "無預設路由"
}

probe_firewall() {
    if command -v ufw &>/dev/null; then
        ufw status 2>/dev/null | head -3 || echo "ufw: 無法查詢狀態"
    elif command -v firewall-cmd &>/dev/null; then
        echo "firewalld: $(firewall-cmd --state 2>/dev/null || echo '無法查詢')"
    else
        echo "未偵測到防火牆管理工具"
    fi
}

# 產出 project-context.md
cat > "$OUTPUT_FILE" << EOF
# project-context.md — 環境探測報告

> 專案名稱：$PROJECT_NAME
> 探測時間：$TIMESTAMP
> 探測主機：$(hostname)
> 探測帳號：$(whoami)
> 狀態：待確認

---

## 標準符合度（對照 DEPLOY_STANDARD）

$(check_os)
$(check_python)
$(check_url "GitLab（內網）" "${GITLAB_URL:-}")
$(check_url "內部 PyPI mirror" "${PYPI_MIRROR_URL:-}")

## 作業系統

$(probe_os)

## Python 環境

$(probe_python)
虛擬環境路徑：/opt/apps/$PROJECT_NAME/venv/

## 運行中的關鍵服務（systemd）

$(probe_services)

## 運行中的 Docker Container

$(probe_containers)

## 找到的 Compose 檔案

$(probe_compose)

## 磁碟空間（/opt）

$(probe_disk)

## 網路路由

$(probe_network)

## 防火牆狀態

$(probe_firewall)

## 部署目標目錄

/opt/apps/$PROJECT_NAME/

---

## 人工確認清單

以下項目請在開始開發前由 IT 人工確認：

- [ ] 關鍵服務清單已確認（上方列出的服務皆為已知服務）
- [ ] 部署目標目錄已確認
- [ ] 網路環境已確認（離線 / 內網）
- [ ] 備份策略已確認
- [ ] 「標準符合度」中的 ❌ 與 ⚠️ 項目皆已處理或確認可接受
- [ ] 關鍵 Docker container 已確認（上方列出的 container 皆為已知）

全部確認後，請將檔案開頭的「狀態：待確認」改為「狀態：已確認」。

確認人：_______________　　日期：_______________

---

> 此文件由 env-probe.sh 自動產出，請勿手動修改探測結果部分。
> 人工確認清單部分需由 IT 填寫後才能開始開發。
EOF

echo "✅ project-context.md 已產出"
echo "請 IT 人工確認後才能開始開發。"
