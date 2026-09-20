# loop_kit — 補上你 harness 缺的那一層

## 這套東西在你的架構裡的位置

你原本的 harness 有三層，都做對了：

| 層 | 元件 | 作用 |
|----|------|------|
| 規則層 | `CLAUDE.md`、`DEPLOY_STANDARD.md`、`SYSTEM_STANDARD.md` | 行為約束，24 小時生效 |
| 安全層 | `deploy-guard` agent、`rollback.sh` | 攔截與回滾 |
| 工具層 | `env-probe.sh`、`setup.sh`、`audit-log.sh` | 執行動作 |

缺的是第四層：

| 層 | 元件 | 作用 |
|----|------|------|
| **控制層** | **`DONE.md`、`verify.sh`、`loop.sh`** | **判定完成、自動重試、持久化狀態** |

護欄你已經有了，這套補的是軌道。

---

## 安裝

```bash
# 1. 複製到專案根目錄
cp loop.sh verify.sh /opt/{project}/
cp loop.conf.example /opt/{project}/loop.conf
cp DONE.md /opt/{project}/DONE.md
chmod +x /opt/{project}/{loop.sh,verify.sh}

# 2. 填寫設定
vi /opt/{project}/loop.conf      # PROJECT_NAME、SERVICE_PORT
vi /opt/{project}/DONE.md        # 完成條件，這步不可跳過

# 3. 依賴
sudo apt install sqlite3 curl
pip install ruff black pytest

# 4. 驗證器單獨試跑（還沒呼叫 AI，零風險）
./verify.sh
```

---

## 使用

```bash
./loop.sh "把設備清單頁面加上依機房篩選的功能"   # 開一個 run
./loop.sh --resume                              # 接續未完成的
./loop.sh --dry-run                             # 只驗證不呼叫 AI
./loop.sh --status                              # 看歷史與 ticket
```

---

## 它補上的五個缺口

**完成條件**：`DONE.md` 把「什麼叫做完」寫成機器可驗證的 gate。沒有這份檔案 `loop.sh` 拒絕啟動——因為沒有 done criteria 的迴圈只是讓 AI 無限做工。

**驗證器**：`verify.sh` 是整套的核心。Loop Engineering 的關鍵洞見是**驗證器才是瓶頸，不是模型**。生成器可以廉價地跑很多次，但如果沒有東西能判斷結果好壞，跑再多次也不產生價值。

**自動重試**：`loop.sh` 把驗證失敗的原始輸出餵回給 agent，要求它先診斷根本原因再修正。這把你 `CLAUDE.md` 裡「同一解法最多試 2 次」的約定從 prompt 層級提升為**機械強制**——不再依賴 AI 自己遵守。

**原地打轉偵測**：連續兩次產生相同的失敗組合就硬性退出。這是 prompt 層的「死迴圈防護」做不到的事，因為 AI 判斷不了自己在重複。

**狀態持久化**：SQLite 取代人工維護的 `claude-progress.txt`。每次 run、每次 attempt、每個未解決的問題都有結構化紀錄，跨 session 不遺失，也能用 `--status` 直接查。

---

## 硬性退出條件

迴圈遇到以下任一情況立即停止呼叫人工，不再重試：

| 退出碼 | 狀態 | 條件 |
|--------|------|------|
| 0 | passed | 全部 gate 通過 |
| 3 | timeout | 單次執行超時 |
| 4 | blocked | 受保護檔案被修改 |
| 5 | stuck | 連續兩次相同錯誤 |
| 6 | exhausted | 嘗試次數用盡 |

每一種非零退出都會自動開立 ticket 進資料庫。

---

## 關於 UI/UX

`verify.sh` 的 G5 gate 掃描 `templates/` 和 `static/` 有沒有外部資源引用，直接對應你 `SYSTEM_STANDARD.md` 的「不依賴外部資源」原則。這條 gate 的存在讓「Tailwind 用 CDN」這種事**在迴圈裡就被擋下來**，不會等到內網斷線才發現。

但迴圈不驗 UI 好不好看。`DONE.md` 底部的「人工驗收」區列的是只有你能判斷的事——視覺一致性、互動流暢度、RWD、無障礙、語系切換。

這是刻意的分工。迴圈負責把「能跑、安全、沒壞」這些機械性的事自動處理掉，把你的時間完整留給「好不好看、好不好用」——那才是需要人的部分。

---

## 下一步（本版尚未涵蓋）

- **自動觸發**：目前還是你手動下 `./loop.sh`。加上 cron 或 systemd timer，就能做到「你不在時迴圈也在跑」。
- **上下文壓縮**：長 run 會撞 context 上限，需要在 agent 層做 compaction。
- **平行 sub-agent**：一個改前端、一個改後端、一個跑測試，用 git worktree 隔離。

這三件事建議等這一版跑順了再加。先讓單一迴圈穩定運轉，比一次堆滿功能更重要。
