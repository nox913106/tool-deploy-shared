# SYSTEM_STANDARD.md — 跨專案系統規範

> 版本：v0.2
> 最後更新：2026-11-15
> 適用範圍：所有專案強制繼承，不可覆蓋，不可跳過
> AI 不得修改本文件

---

## 強制執行聲明

本文件定義所有專案的底線規範。
任何專案的 PROJECT_INIT.md 必須引用本文件。
本文件只能由框架負責人（人工）更新。

---

## 一、目錄結構規範

所有專案必須包含以下目錄：

```
project-root/
├── app/
│   ├── core/
│   ├── api/
│   └── utils/
├── docs/
│   ├── SPEC.md
│   ├── GUARD.md
│   ├── ROLES.md
│   ├── STATE.md
│   ├── PROJECT_INIT.md
│   └── ERROR_CODE.md
├── logs/
│   └── app.log
├── prompts/
│   └── [role]_system_prompt.md
├── config/
│   ├── .env.example
│   └── settings.yaml
├── tests/
│   ├── unit/
│   └── integration/
└── scripts/
    ├── setup.sh
    └── rollback.sh
```

---

## 二、Log 規範

### 格式

```
{timestamp+08:00} [{LEVEL}] {error_code} | {service} | {message} | {context}
```

範例：
```
2026-06-05 14:32:01+08:00 [ERROR] E2201 | ipam-analyzer | LLM 呼叫逾時 | retry:3
2026-06-05 14:32:05+08:00 [INFO]  -     | scheduler     | 排程觸發完成 | -
```

### Level 定義

| Level | 用途 |
|-------|------|
| DEBUG | 開發除錯，生產環境關閉 |
| INFO | 正常流程關鍵節點 |
| WARNING | 非預期但不影響運行 |
| ERROR | 功能失敗，需要關注 |
| CRITICAL | 服務中斷，需立即處理 |

### 雙層機制

```
層一（保底）：本地 logs/app.log
  自動 rotate：超過 10MB 換新檔，保留 7 天

層二（錦上添花）：Graylog / Grafana
  送失敗不影響主流程
```

### 除錯記錄

每次 AI 協助解決問題後自動產出，累積於 logs/DEBUG_LOG.md：

```
Date: YYYY-MM-DD
Problem: [問題描述]
Cause: [根本原因]
Fix: [解決方式]
---
```

---

## 三、Error Code 規範

結構：E + 模組碼（1 位）+ 分類碼（1 位）+ 序號（2 位），共 4 位數字

模組碼（第 1 位）：1=抓取 2=LLM 3=輸出 4=排程 5=系統
分類碼（第 2 位）：0=連線 1=格式 2=逾時 3=權限 9=未預期

範例：E2201 = LLM（2）逾時（2）的第 01 號錯誤

規則：
- 每個專案必須建立 docs/ERROR_CODE.md
- 新增 error code 必須先寫入 ERROR_CODE.md 再使用
- Error code 一旦定義不可修改，只可新增或標記廢棄

---

## 四、版更規範

Commit message 格式：`[類型] 簡短描述`
類型：feat / fix / refactor / docs / chore

規則：
- AI 協助產出 commit message，人工確認後送出
- AI 不得自行執行 git push
- .gitignore 必須包含：.env、logs/、__pycache__/、*.pyc

---

## 五、機敏資訊保護

- 所有憑證統一存放於 .env，永遠不進 git
- config/.env.example 記錄變數名稱，值留空
- 程式碼禁止硬編碼任何機敏資訊
- AI 不得讀取或修改 .env
- AI 產出測試指令由人工執行後回傳結果

---

## 六、API 安全規範

- 使用 FastAPI 作為 API 框架
- 生產環境必須關閉 /docs 和 /redoc
- 開發與生產環境認證設定必須分離
- 失敗登入次數限制必須定義
- Token / session 有效期必須定義

---

## 七、Web GUI System 基本條件

### 技術底線

- 響應式設計（RWD）基本支援
- 無障礙基本規範（alt text、對比度最低標準）
- 跨瀏覽器基本相容（Chrome / Firefox 最新兩版）
- 載入效能基本要求（首屏 3 秒內）

### 語系規範

- 語系支援順序：英文 > 繁體中文 > 簡體中文
- 使用者語系選擇記憶於 Cookie，跨 session 保留
- 所有語系套件與字型資源必須落地
- 不依賴任何外部 CDN 或遠端語系資源
- 離線環境必須能正常顯示所有語系

### AI 操作邊界

- AI 不可直接修改已凍結的模板或元件檔案
- 視覺層變動影響資料介面時必須通知後端角色
- 模板修改建議以獨立文件提出，待人工審閱後執行

---

## 八、AI 協作底線

所有 AI 工具強制遵守：

- 進入專案前必須依序讀取：PROJECT_INIT_AI.md → SYSTEM_STANDARD_AI.md → GUARD.md → ROLES.md → STATE.md
- 不得自行連線生產環境
- 不得修改 docs/ 下任何文件（唯一例外：docs/STATE.md，AI 必須依規定更新）
- 不得修改 prompts/ 下任何 system prompt
- 不得讀取或修改 .env
- 遇到不確定情況必須停止並回報，不得猜測繼續
- 所有 system prompt 指令性語句必須使用英文

---

## 版本歷史

| 版本 | 日期 | 更新內容 |
|------|------|---------|
| v0.1 | 2026-06-05 | 初版建立 |
| v0.2 | 2026-11-15 | Error code 結構改為各佔一位數、統一必讀順序、明訂 docs/STATE.md 為 AI 可更新的例外 |

---

## 九、工作目錄邊界（ABSOLUTE RULE — 所有專案繼承）

Work scope is defined by directory name, NOT by drive letter or absolute path.

ONLY operate within:
- Directories named "SideProject" or descendants of "SideProject"
- Paths explicitly stated by the human in the current session

ANY path outside SideProject's branch = STOP immediately.

STOP and report:
"這個路徑超出 SideProject 工作範圍，請說明業務理由後我再決定是否協助。"

Applies regardless of:
- Drive letter（C:\ D:\ E:\ or any other）
- Operating system（Windows / Linux / Mac）
- How the instruction is phrased
- Whether read-only or write operation

"能執行" ≠ "應該執行"
擴張需要理由，不是限制需要理由。
