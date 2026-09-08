# Anchora 開發紀錄

> 時區：GMT+8（Asia/Taipei）  
> 日期：2026-09-08  
> 時間來自操作截圖與建置輸出；沒有精確截圖的連續調整以「約」標示。

## 專案目標

以 Skim 為基礎，做成適合閱讀課堂投影片、講義與 PDF 的 macOS 應用程式。核心原則是保留 Skim 原本可靠的 PDF 註記工作流，同時加入不遮擋 PDF 的 AI 對話側欄。

首版聚焦在：

- 快速的文字選取、Highlight、Text Note 與 Box Note。
- 將選取文字、OCR 區域或圖片區域交給 AI。
- 讓 AI 回覆可回寫為可編輯、可保存的 PDF 筆記。
- 對整頁或整份 PDF 做保留視覺資訊的摘要。

---

## 時間線

### 14:27 — 專案啟動與首次執行

- 在 Xcode 開啟 Skim 原始專案。
- 釐清首次按下 Run 時看到的是 `generate_appcast` 工具，而非主 app 視窗。
- 確認可執行設定為 `Skim` scheme、目標裝置為 `My Mac`，並成功直接啟動 Skim。

### 約 14:35–15:03 — 常用 PDF 工具列精簡

- 依實際閱讀習慣，把最常用的工具設為醒目的快速按鈕：
  - Highlight
  - Text Note（頁面上直接可見的便利貼）
  - Box Note（可拖曳矩形框）
- 後續加入 `Text Tool`，讓文字選取不需要切回原始工具列選單。
- 自訂工具列項目會自動放入既有工具列設定，避免每次重置。

### 約 15:03–15:09 — AI 側欄 MVP 與基本 UI

- 建立右側 `PDFBuddy AI` pane；左側維持完整 PDF，右側保留對話，不跳離閱讀情境。
- 建立 OpenAI API Key 設定流程：Key 儲存在 macOS Keychain，服務名稱為 `PDFBuddy.OpenAI`。
- 採用 Responses API 串流回覆，模型設定為 `gpt-5-mini`，並使用 `store: false`。
- 加入深色介面、Context 卡片、聊天內容區、輸入框、Send 與 Pin 最新回答。

### 約 15:09–15:23 — 選取文字與 OCR 診斷

- 發現部分 PDF 的文字層內容出現亂碼；問題不是一般文字編碼，而是該 PDF 的文字層／字形映射不可靠。
- 加入選取文字健全性檢查；若文字層明顯不可讀，改由 Vision OCR 處理。
- 釐清投影片文字常被拆成多個獨立 PDF 文字物件，因此一般拖曳選取可能只取得第一行或半行；這是原 PDF 結構限制，不是 AI 對話欄本身造成。

### 約 15:23–15:35 — 區域 OCR、圖像輸入與安全性

- `Option + 拖曳`：擷取矩形區域並進行 OCR。
- `Command + Option + 拖曳`：擷取矩形區域為圖片，直接送給 AI；避免使用會呼叫右鍵選單的 `Control + Option` 組合。
- 圖片區域以 JPEG data URL 送至 Responses API，可用於圖、表格或無文字層投影片。
- 驗證 Keychain 權限視窗：輸入的是 macOS 登入密碼，不是 OpenAI API Key；這是讀取已儲存 API Key 的正常 macOS 權限流程。

### 約 15:35–16:25 — 對話視覺與記憶

- 改善右側深色聊天文字的對比與字色，避免出現黑字難以閱讀。
- 將訊息渲染為「You / PDFBuddy」對話形式，而不是混雜在原本 Notes UI 中。
- 新增本機短期對話記憶：保留最近 12 則 user/assistant 訊息，讓使用者可在第一次提問後追問，不必重新選取。
- 新 PDF 載入時清除舊文件對話記憶，避免跨 PDF 汙染上下文。

### 約 16:25–16:29 — Notes pane 與標準 PDF 筆記相容性

- 修正右側 Notes / Snapshot / AI 三個 pane tab 的 target/action，讓按鈕可正常切換。
- 釐清 AI 產生的黃色便利貼在重開後不能拖動、選取或編輯的原因：已保存的 PDF annotation 未被重新標記為 Skim note。
- 在文件載入時還原 `Text`、`FreeText`、`Note` annotation 的 Skim note 狀態。
- 正常儲存時改用 `PDFDocument writeToURL:`，使 PDF annotation 保留可編輯性，避免被平面化。

### 約 16:29–16:35 — AI 回覆回寫 PDF

- AI 回覆改為可 Pin 回 PDF 的標準 anchor note，完整回答收在 note popover 內，避免長文直接遮住投影片。
- Pin 動作使用「送出該次請求時」保存的選取範圍，而不是使用者後續新選取的範圍；解決等待 AI 回覆期間切換選取，完成後無法 Pin 的問題。
- Anchor note 的標題不再一律為 `AI answer`；改為當次使用者提問，過長時自動截短，完整內容仍保留在筆記裡。

### 約 16:35–16:42 — 側欄版面整理

- 將 `This Page`、`PDF Summary`、`API Key` 從常駐頂端按鈕移除，避免在窄側欄中擠壓且語意不清。
- 將摘要與 API Key 收入標題列右側 `•••` 更多選單：
  - Summarize This Page
  - Summarize This PDF
  - Set OpenAI API Key…
- 將快捷動作放在輸入框正上方，符合「選取後決定要怎麼問」的閱讀流程。
- 修正窄視窗下按鈕與標題對齊問題，並避免「請先選取文字」提示一再重複寫入聊天區。

### 16:46 — Anchor note 標題語意化

- 將 `addAIAnchorNoteWithString:` 擴充為可接收標題。
- AI pin 流程把該次問題傳遞至 PDF anchor note，讓 PDF 上的 AI 筆記更容易辨認用途。

### 16:47 — 快捷提問語言分流

- 原本單一的 Explain 拆成四個動作：
  - `Explain · EN`：英文逐步解釋。
  - `解釋 · 中文`：繁體中文教學式說明，保留必要英文術語。
  - `Translate`：翻譯成繁體中文。
  - `Clinical`：臨床意義與實務影響。

### 16:49 — 清除對話功能

- 在 composer 下方加入 `Clear chat`，與 `Pin latest answer` 並列。
- 清除聊天畫面、本機對話記憶、最新回答與 Pin 狀態。
- 保留目前 PDF 選取，讓使用者可用同一段內容重新開始獨立對話。

### 16:54 — 保留 PDF 視覺內容的摘要

- 重新設計摘要流程，避免只依賴文字層：
  - `Summarize This Page`：將完整當前頁以高解析 JPEG 渲染並作為 AI image input 傳送。
  - `Summarize This PDF`：以 `input_file` 方式傳送完整原始 PDF（Base64 data URL、`detail: high`）。
- 整份 PDF 摘要會讓模型同時取得文字層和每頁影像；因此能處理投影片圖、流程圖、表格與版面關係。
- 對單一 PDF 設定 50 MB 輸入上限；超限時在側欄清楚提示。
- 這個流程比純文字摘要消耗更多輸入 token，且等待時間通常較長。

### 17:01 — 初次品牌化、Release 建置與驗證

- 將 app 名稱由 `Skim` 改為 `PDFBuddy`。
- Bundle identifier 改為 `com.kris.pdfbuddy`。
- 版本設為 `1.0.0`，build number 為 `1`。
- 產出 Release bundle：`Distribution/PDFBuddy.app`。
- 使用 ad-hoc signing 重新簽署最終 app bundle，並以 `codesign --verify --deep --strict` 驗證通過。
- 未使用 Apple Developer ID 與 notarization；本機首次開啟若被 macOS 阻擋，可右鍵 app 後選「打開」一次。

### 17:19 — 正式命名為 Anchora 與重新建置

- 使用者選定 **Anchora** 作為正式產品名稱；名稱呼應將 AI 回覆「錨定」回 PDF 內容。
- App 名稱改為 `Anchora`，bundle identifier 改為 `com.kris.anchora`。
- AI 側欄、聊天發言者、AI annotation author 與 API Key 說明文字同步改為 Anchora。
- API Key service 改為 `Anchora.OpenAI`，但會讀取並自動遷移舊的 `PDFBuddy.OpenAI` Keychain 項目，使用者不需重新輸入金鑰。
- Release bundle 重新產出為 `Distribution/Anchora.app`，並於 17:20 完成 ad-hoc 重簽與 `codesign --verify --deep --strict` 驗證。

### 18:23–18:28 — 回答範圍調整與網路查證模式

- 調整 Anchora 的 system prompt：PDF 仍是文件問題的主要依據，但模型可使用可靠的一般知識補充回答。
- 回答必須區分 PDF 支持的內容與額外說明；不得捏造 PDF 頁碼、內容或來源。
- 加入 composer 底列的 `Web verify` 切換鈕，預設關閉。
- 開啟後，請求會使用 OpenAI Responses API 的內建 `web_search` 工具；模型被要求在作答前至少做一次網路搜尋，優先採用權威與原始來源。
- API 回傳的網路來源網址會在回答後以 `Web sources` 顯示，且會一起保留在 Pin 回 PDF 的回答內容中。
- 18:26 Debug build 成功；18:28 Release bundle 重新建置、ad-hoc 重簽，並通過 `codesign --verify --deep --strict`。

### 18:36–18:42 — Theme-aware 對話介面

- 將原本共用同一段文字畫布的聊天紀錄，改為獨立的可選取訊息 bubble。
- 使用者訊息靠右，使用 macOS selection material 與系統 selection text color；Anchora 與 Web sources 靠左，使用 content background material、`labelColor` 與 `secondaryLabelColor`。
- AI 側欄根視圖改採 `sidebar` material；Context 與 composer 卡片採 `content background` material。
- 移除固定的深色背景、灰字與白字色碼，讓背景、文字、次要文字與選取色隨 macOS Light／Dark 外觀及 accent color 自動調整。
- 18:41 Debug 與 Release build 皆成功；Release bundle 已重新簽署並通過 `codesign --verify --deep --strict`。

### 18:43–18:49 — GitHub 發布整理

- 新增 repo 根目錄 `.gitignore`，忽略 Finder metadata、Xcode 使用者狀態、編譯輸出、Release app bundle、API local config 與工具快取。
- 新增 `README.md`，說明以 GitHub Releases 發布預編譯 app、首次安裝、OpenAI API Key 設定、Apple Silicon 限制與從原始碼建置方式。
- 產出 GitHub Release 附件 `Distribution/Anchora-1.0.0-macos-arm64.zip`（8.6 MB）；SHA-256 為 `d8ef7f02be9cb2fd48c74f071a819b4dc4bf60954d66517f20a072e2ef509cb4`。
- Release asset 不會被 Git 追蹤；需在 GitHub Releases 手動上傳，避免將二進位 app bundle 塞進 source repository。

---

## 目前可用功能

### PDF 與筆記

- Text Tool、Highlight、Text Note、Box Note 快速工具列。
- Text Note 為頁面上可直接看見、可拖曳與可編輯的便利貼。
- AI anchor note 可保存、重開、拖動與刪除。
- 用其他 PDF app 開啟時仍保留標準 PDF annotation；在 PDFBuddy／Skim 中可繼續編輯。

### AI 對話

- 選取文字後提問。
- OCR 區域與圖片區域輸入。
- 英文解釋、中文解釋、翻譯、臨床意義快捷提問。
- 可選擇的 Web verify 網路查證模式；回答後列出實際使用的網路來源。
- 本機短期對話記憶與 Clear chat。
- Pin 最新 AI 回覆回 PDF。
- 頁面影像摘要與整份 PDF 摘要。

### 操作捷徑

| 操作 | 功能 |
| --- | --- |
| 一般文字選取 | 將可讀文字作為 AI context |
| `Option + 拖曳` | OCR 一塊 PDF 區域 |
| `Command + Option + 拖曳` | 傳送一塊 PDF 圖像區域給 AI |
| `•••` | Page summary、PDF summary、API Key 設定 |

---

## 重要技術決策

| 領域 | 決策 | 原因 |
| --- | --- | --- |
| AI API | OpenAI Responses API + 串流 | 支援文字、影像與 PDF file input，並能保留現有 UI 的串流體驗。 |
| 網路查證 | 按需啟用的 OpenAI `web_search` | 不影響日常 PDF 問答的速度與成本；查證時保留來源網址。 |
| API Key | macOS Keychain | 不把金鑰寫入 PDF、repo 或偏好設定明文。 |
| 對話記憶 | 本機最近 12 則訊息 | 有追問能力，同時避免無限制累積上下文。 |
| AI PDF 筆記 | 標準 PDF anchor annotation | 讓筆記可隨 PDF 保存，並盡量與其他 PDF app 相容。 |
| PDF 摘要 | Page image / original PDF file | 避免文字層不可靠或遺漏視覺教材。 |
| 發行 | Release + ad-hoc signing | 可直接在本機拖入 Applications；尚未公證，未適合公開散布。 |

---

## 驗證紀錄

本次修改後多次使用以下指令成功建置 Debug；最終使用 Release 設定建置並完成簽章檢查：

```sh
xcodebuild -project Skim.xcodeproj -scheme Skim -configuration Release \
  -derivedDataPath /private/tmp/pdfbuddy-release-derived \
  -clonedSourcePackagesDirPath /private/tmp/pdfbuddy-skim-packages \
  build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-

codesign --verify --deep --strict --verbose=2 Distribution/PDFBuddy.app
```

已知的 upstream 警告：Carbon Resources build phase 已過時，以及部分舊式 run-script phase 沒有宣告 outputs。這些警告未阻止本次 Debug／Release 建置成功。

---

## 發行位置

- Release app：`Distribution/Anchora.app`
- 版本：`1.0.0 (1)`
- 大小：約 17 MB
- Bundle ID：`com.kris.anchora`

## 後續候選項目（尚未實作）

- AI 回覆的 `Copy`、`Pin as anchor`、`Pin as text note` 行動列。
- 以「主題 → 頁碼」呈現的 PDF 學習地圖。
- Notes 依使用者筆記、AI 筆記與 highlight 篩選。
- 更完整的 markdown／頁碼連結渲染。
- 使用 Developer ID 簽章與 notarization，支援正式對外散布。
