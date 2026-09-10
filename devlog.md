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

## 2026-09-09

### 09:00–10:30 — Scientific Reading profile

- 將原本偏講義閱讀的 Anchora AI 擴充為可切換的兩種閱讀 profile：
  - `Study`：用於投影片、講義、一般 PDF 的解釋、翻譯與臨床連結。
  - `Scientific`：用於研究論文的證據導向閱讀。
- Scientific profile 的快捷動作改為：`Paper`、`Question`、`Hypothesis`、`Methods`、`Figure`、`Evidence`。
- 這些動作不再一律依賴反白選取：
  - 沒有選取時，`Paper`、`Question`、`Hypothesis`、`Methods`、`Evidence` 會使用整份 PDF。
  - `Figure` 沒有選取時，會分析目前頁面的完整渲染圖；有選取時，則分析被框選的圖像區域。
  - 有文字選取時，除了 `Paper` 外會優先針對該段做精讀，保留快速局部問答的工作流。
- 新增完整 PDF 的 Paper map：要求模型依序重建研究問題與 knowledge gap、研究目標、主要假設／問題、研究與實驗方法、關鍵圖表與證據、直接證明了什麼、作者詮釋、限制與未解問題。
- Scientific system prompt 明確要求把「直接結果、作者詮釋、合理推論、尚未證明」分開；圖表回答必須處理 x/y 軸、單位、組別／控制、統計或不確定性、趨勢、可支持的結論與限制。
- Scientific 完整 PDF 請求的輸出上限提高到 16,000 tokens；一般回覆維持 8,000 tokens，避免短答案把論文架構截斷。

### 10:30–11:10 — 語言設定與 AI 請求可見性

- 把原先 Study mode 中分開的英文解釋與中文解釋按鈕整合為單一全域回覆語言設定。
- 右上 `•••` 選單加入 `Response language` 子選單，可選 `繁體中文` 或 `English`；設定以 `NSUserDefaults` 保存，切換 Study／Scientific 或重新開啟 app 都會沿用。
- 快捷按鈕依當前語言產生回答；`Translate` 則翻到目前設定的語言，若來源本來就是該語言，改為清楚的同語言改寫。
- 請求開始時新增明確的階段訊息：`Preparing…`、`Preparing the complete PDF…`、`Uploading PDF to Anchora…`、`Anchora is reading…`，讓完整 PDF 上傳或模型分析期間不再像無回應。
- Send 按鈕在請求期間改成 `Stop`；停止會取消 URL session task、保留已收到的文字，並在聊天中留下已停止提示。

### 10:40–11:15 — 開檔記憶體暴增與 layout 迴圈修復

- 觀察到某些 PDF 開啟時 Anchora 可吃到 25 GB 記憶體、CPU 長時間滿載，並造成彩虹圈與檔案無法開啟。
- 根因為 AI 快捷按鈕列使用 `NSStackView` 的 arranged-subview/fitting-size 路徑，與側欄重建／Auto Layout 互相觸發，形成重複量測與配置迴圈。
- 快捷列改為一般 `NSView`，按鈕以直接 constraints 排列，不再透過 `addArrangedSubview:` 或 `fittingSize` 參與遞迴量測。
- 按鈕建立方式改為有明確 frame 的 `NSButton`，避免 AppKit 在載入視窗的過程中反覆詢問 intrinsic size。
- 後續實測開檔後 Anchora 約 205 MB，峰值約 337 MB；這是含 PDFKit、側欄與完整頁面 render 的合理短暫峰值，並已不再呈現線性無限成長。

### 11:15–12:00 — 回覆串流、完整 PDF 與 Pin 流程穩定化

- 保留 Responses API SSE 串流，同時為 `response.completed` 加入最終 response 文字的 fallback，避免 delta event 遺失時已完成的回答沒有進入 UI。
- 完整 PDF 上傳與分析改為可取消、可顯示進度的流程；對話輸入與快捷列在請求中維持一致的 enabled/disabled 狀態。
- `Build Paper Map` 的完整回答可以直接 Pin 為標準 PDF anchor note；anchor title 使用當次問題，而不是一律的 `AI answer`。
- 修正完整回答在 sidebar 尚未渲染、但已被 Pin 到 note 的競態問題：主執行緒上同步加入聊天訊息，並在串流結束後強制刷新聊天 layout。

### 12:00–13:15 — Bubble 版面、來源跳轉與裁切修復

- 聊天 bubble 的文字高度不再交給 `NSTextField` 在 `NSStackView` 中猜測；改依 bubble 可用寬度用 `boundingRect` 計算，再更新明確高度 constraint。
- 側欄被拉寬或縮窄時，重新計算所有 assistant/user bubble 的可用寬度與文字高度，因此長回答會隨可用欄寬擴張，而不是固定在過窄的欄位。
- 對 assistant 回覆加上專用的 source footer，並為 body 與 footer 建立獨立的 top、height、bottom constraints；避免 `PDF source` 疊在最後一行回答上，或被下一排快捷列裁掉。
- 來源跳轉改為低視覺重量的 `↗ p. N` 文字連結，保留「點擊回到 PDF 頁面」的功能，但不把它做成厚重的按鈕。
- 聊天區在每次文字更新、狀態更新與完成後重算 layout 並捲到最新訊息，改善「結果已取得但 bubble 空白／文字被切掉」的問題。

### 13:17–13:25 — Anchora 1.1.0 Release

- `CFBundleShortVersionString` 升為 `1.1.0`；`CFBundleVersion` 升為 build `2`。
- Release 包含 Scientific profile、全域回覆語言、完整 PDF/Paper map、可取消與可見狀態的請求流程、記憶體配置迴圈修復，以及 sidebar bubble/source footer 的 layout 修復。
- 13:24 命令列 Release build 成功，並在 13:25 封裝為 `Distribution/Anchora-1.1.0.app`（約 16 MB）；不開啟 Xcode GUI，避免干擾使用者自行檢查專案。

### 23:30 — Paper Map navigator 與 Evidence chain（未重新封裝）

- Scientific 的 `Paper` 動作現在要求固定的八個 Markdown H2 區段；回覆完成後會被解析為可選擇的 Paper Map 節點，而不是停留為一大段 chat 文字。
- 每個節點可在固定高度、內部可捲動的閱讀卡中展開；右側的 `Jump to supporting PDF page…` 可跳回該節列出的 PDF citation 頁面。
- Map 中會以較高辨識度標示 `Direct evidence`、`Author interpretation`、`Reasonable inference`、`Unproven / limitation`，將論文的證據鏈從作者主張與合理推論中分開。
- 完整原文仍保留在對話記憶與 `Pin latest answer`，但 chat bubble 會收斂為「Paper Map ready」狀態，避免它再次撐滿整個 sidebar。
- 隨後改為完全移除該次 Paper Map 的串流 assistant bubble，只保留 Paper Map navigator；原回答仍保存在本機對話記憶與 Pin 流程中。
- Paper Map 現在要求每個 `Direct evidence` 附上一句 8–28 words 的 `Source quote`。該引文在 Map 內是可點擊連結：會跳至 citation 對應頁，並在 PDF text layer 可匹配時選取／反白原句；若文字層不一致，安全退回到該頁而不製造假反白。
- 針對過去的 sidebar layout 問題，Map 不放入 chat 的 `NSStackView`；隱藏時採嚴格零高度、顯示時則允許在極矮側欄中讓位給 composer，避免 constraint fight。
- Scientific 的 `Evidence` 按鈕保留短標籤以適應窄側欄；tooltip 說明它會要求四層 evidence chain。這兩項功能等待下一次成功 Debug／Release build 才會封裝。

### 22:35 — 可保存的 AI 模型選擇器（未重新封裝）

- 在 `•••` 更多選單加入 `AI model (目前模型)` 子選單；目前提供經過 Anchora 的 Responses／視覺輸入工作流篩選的選擇：
  - `gpt-5.6-luna`：日常 Study 問答，成本優先。
  - `gpt-5.6-terra`：品質與成本的推薦平衡點，適合作為 Scientific 預設。
  - `gpt-5.6-sol`：完整 Paper map、重要論文與深度證據拆解。
  - `gpt-5-mini`：保留為舊的極省成本選項，亦是沒有儲存設定時的安全預設。
- 選擇保存於 `NSUserDefaults` 的 `Anchora.AIModel`。下一次請求才會採用新模型，避免影響正在串流的回覆。
- 若舊設定不存在或模型不在受控清單，會安全回退到 `gpt-5-mini`。
- 2026-09-09 22:35 已完成 Debug command-line build；此項功能尚未重新封裝進前一份 `1.1.0` Release app，待下一次 Release build 一併發行。

---

## 2026-09-10

### 10:40–11:30 — Swift 核心層與 mixed-language target

- 決定不重寫 Skim，改採 **Swift island**：Skim 的 ObjC（PDFView、annotation、document I/O、undo）凍結不動，Anchora 自己的新程式碼一律寫在 Swift。
- 最低系統版本由 `10.13` 提高至 **macOS 14.0**。這是不可逆的決定，換來 async/await 與後續 SwiftUI 的可用性；Apple Silicon 機器本來就到不了 10.13。
- 在既有 `Skim` target 開啟 Swift（`SWIFT_VERSION = 5.0`、bridging header `Anchora/Anchora-Bridging-Header.h`、generated header `Anchora-Swift.h`），不新增 target。Debug 用 `-Onone`，Release 用 `-O` + `wholemodule`。
- 語言模式刻意留在 Swift 5：AI 層會把 callback 交還給長生命週期的 AppKit 物件，Swift 6 strict concurrency 會要求改寫 Skim 自己擁有的程式碼。

### 建立 `Anchora/` Swift 核心（815 行，零 AppKit、零 Skim 型別）

- `AnchoraSettings`：reading profile、回覆語言、AI model 的 `NSUserDefaults` 保存與驗證。未知或不存在的 model 一律安全回退到 `gpt-5-mini`。
- `AnchoraCredentials`：Keychain 讀寫與 `PDFBuddy.OpenAI` → `Anchora.OpenAI` 的舊金鑰遷移。
- `AnchoraPrompts`：所有 system instruction、快捷動作 prompt、摘要 prompt、Paper map prompt 與歡迎訊息集中一處，不必翻 AppKit layout 程式碼就能檢視 Anchora 的閱讀行為。
- `AnchoraPaperMap`：Paper map 的段落切分與 `[PDF p. X]` citation 解析。由呼叫端傳入頁面 label 陣列，因此完全不依賴 PDFKit，可獨立測試。
- `AnchoraResponsesClient`：一次完整的 Responses API 串流。取代原本手寫的 `NSURLSessionDataDelegate` + SSE buffer，改用 `URLSession.bytes` 與 `for try await`；request 組裝、delta 批次化（0.12 秒）、web source 收集、HTTP/串流錯誤對應全部在此，呼叫端只看到 status／delta／finish 三個 main-thread callback。

### `SKRightSideViewController.m` 瘦身

- 2,256 行 → **1,906 行**（AI 相關淨減約 500 行）。
- 移除的屬性：`aiSession`、`aiTask`、`aiEventData`、`aiPendingStreamText`、`aiStreamRenderScheduled`、`aiWebSourceURLs`、`aiReadingProfile`、`aiResponseLanguage`。
- 移除的方法：`consumeAIEvents`、三個 `URLSession` delegate、`appendAIText:`、`collectWebSourcesFromObject:`、`webSourcesText`、`outputTextFromCompletedResponse:`、`availableAIModels`、`responseLanguageInstruction`、`storedOpenAIAPIKeyWithStatus:`，以及 `SKPaperMapSectionDefinitions` 與兩個 enum。
- 取消請求改為只呼叫 `[self.aiClient cancel]`；UI 重置統一在 `finishAIRequestWithText:webSources:errorMessage:cancelled:` 一處處理，不再散落在 delegate 與 cancel 兩邊。
- 送出請求的流程改為組裝 `AnchoraRequest` 後交給 `AnchoraResponsesClient`，view controller 不再直接接觸 JSON body、HTTP header 或 SSE。

### 修正 Paper map 的 Limitations 段落解析

- 移植時以獨立測試檢查八個 H2 段落，發現 `Limitations and unanswered questions` **從來沒有被切出來過**：原 regex 的 `and` 只存在於 `alternative explanations` 分支內，因此 prompt 實際要求的標題無法匹配，該段內容一直被併入前一段 `Authors’ interpretation`。
- 已修正為 `Limitations?(?:,?\s*alternative\s+explanations?)?(?:,?\s*and)?\s*…`，兩種寫法都能匹配。八段切分與非結構化回覆的 fallback 皆通過測試。

### 驗證

- Debug 與 Release 皆建置成功；`SKRightSideViewController.m` 僅剩兩個既有警告（未使用的 `pdfView`、`clickedOnLink:` 參數型別），與本次修改無關。
- Release bundle 以 ad-hoc 重簽後通過 `codesign --verify --deep --strict`；`LSMinimumSystemVersion` 已為 `14.0`，大小約 17 MB。

### 後續（尚未進行）

- 第 3 步：把聊天 bubble、Paper Map navigator 與 composer 改成 SwiftUI，塞進 `NSHostingView`。手算 `boundingRect` 高度、body/footer 三組 constraints 與 `refreshChatLayoutAndScrollToBottom:` 屆時可以整批移除。

### 11:30–12:20 — 側欄 UI 改為 SwiftUI

- 聊天紀錄與 Paper Map navigator 改成 SwiftUI，以 `NSHostingView` 掛進既有 AppKit 側欄。AppKit 只負責它們在側欄裡的位置與高度。
- 新增：
  - `AnchoraChatModel`／`AnchoraChatView`：訊息以資料形式存在，bubble 由 SwiftUI 排版。
  - `AnchoraPaperMapModel`／`AnchoraPaperMapView`：段落選單、跳頁選單、evidence 標示與 Source quote 連結。
  - `AnchoraHosting`：提供 ObjC 可呼叫的 hosting view factory。
- `NSHostingView.sizingOptions` 刻意設為空。會回報 intrinsic content size 的 hosting view 會重現當初手寫 chat stack 的量測迴圈：側欄決定寬度 → view 量測文字 → 高度回饋給側欄。現在這兩個 view 完全由外部 constraints 決定尺寸。

### 因此整批刪除的程式碼

- `refreshChatLayoutAndScrollToBottom:`：包含用 `boundingRect` 手算每個 bubble 文字高度、`AnchoraChatBodyHeight` constraint 的更新、以及避開 `fittingSize` 的整段防禦邏輯。
- `appendChatMessageFrom:` 裡建構 bubble 的約 90 行 constraint 程式碼（sender label、body、source footer 的 top/height/bottom 三組 constraint）。
- `flushPendingAIStreamText` 中為了讓 `NSTextField` 在串流 `setStringValue:` 後重新計算高度而做的 `invalidateIntrinsicContentSize` / `setNeedsLayout:` 連鎖呼叫。
- `chatLabelWithString:`、`clearRenderedChat`、`paperMapDetailAttributedString:`、`textView:clickedOnLink:atIndex:`、`showPaperMapSectionAtIndex:`、`selectPaperMapSection:`、`openPaperMapSource:`、`togglePaperMap:`、`appendPendingWelcomeMessageIfPossible`。
- 因為側欄寬度為零時不再需要延後渲染，歡迎訊息的 pending／重試機制也一併移除。
- `SKRightSideViewController.m`：1,906 → **1,508 行**（自本次重構開始累計 2,256 → 1,508）。

### 修正「Hide」之後無法叫回 Paper Map

- 原本 `togglePaperMap:` 收合時會把整張卡片 `setHidden:YES`，而 `Show Paper Map` 按鈕就在那張卡片裡；一旦按下 Hide，除非重新產生一份 Paper Map，否則沒有任何方式把它叫回來。
- 新版收合後保留 34pt 的標題列（`PAPER MAP` + Show/Hide），卡片只有在完全沒有 Paper Map 時才是零高度。

### 驗證

- Debug 與 Release 皆建置成功；Release ad-hoc 重簽後通過 `codesign --verify --deep --strict`，約 17 MB。
- 實際開啟 PDF 執行：常駐約 192 MB、CPU 閒置 0%，主控台沒有 constraint 衝突或 exception。
- 實機確認：AI 側欄可正常切換、Study／Scientific 切換會重建快捷列與標題、重複的提示訊息只會出現一次（`containsText:` 去重路徑）。
- 使用者 bubble、串流回覆 bubble、來源 chip、Web sources 與 Paper Map 需要 API 請求才會出現，改以離線 preview harness 用範例資料渲染真實 view 驗證，避免消耗 API 額度。來源 chip 確認落在回答最後一行下方，不再重疊。

### 12:20–13:10 — 缺陷修正、測試與 1.2.0

**修正串流 client 的 data race。** `pendingDelta`、`flushScheduled`、`finished`、`task` 同時被三個執行脈絡碰觸：串流 task、delta flush task，以及主執行緒的 `cancel()`，且完全沒有同步。以 `NSLock` 保護這四個欄位；`receivedText` 與 `webSources` 維持只在 `run()` 內讀寫，`cancel()` 不再跨執行緒讀它們（取消路徑本來就不使用回覆內容與來源）。

**強化 `AnchoraChatModel` 的索引。** `Clear chat` 取消請求後，仍可能有已在路上的 delta 抵達。所有 `streamingIndex` 的使用改為先驗證範圍，避免越界。

**Anchora 程式碼的編譯警告清為 0**（原 46 個）：`buildAIInterface` 的區域變數 `aiView` 與快捷列的 `button` 遮蔽 Skim 的 ivar、未使用的 `pdfView`、以及只寫不讀的 `webVerificationButton`。

**新增 `Tools/AnchoraCoreTests.swift` 與 `Tools/run-anchora-tests.sh`（59 個檢查）。** 沿用 `StandardAnnotationSmokeTest.swift` 既有的獨立 `swiftc` runner 模式，不動 Xcode 專案。涵蓋：

- Paper map 的八段切分、Limitations 的三種標題寫法、空段落佔位、非結構化回覆的 fallback。
- Citation 解析：單頁、頁碼範圍、逗號分隔、重複去除、超出頁數丟棄，以及羅馬數字／`S1` 這類非數字 label。
- **Prompt 與 parser 的契約**：從 `paperMapPrompt` 抽出它要求的八個標題，逐一確認 parser 認得。Limitations 那個 bug 之所以能存活，正是因為這兩邊沒有任何東西綁住。
- Settings：未設定時回退、拒絕不在清單中的 model、已移除的舊 model 安全回退、profile 跨實例保存。
- Chat：串流生命週期（placeholder → 第一個 delta 取代而非附加 → 後續附加）、Stop 與錯誤在「有／沒有部分輸出」兩種情況下的行為、Paper Map 移除自己的 bubble、Clear chat 之後遲到的 delta 不會崩潰、提示訊息去重。

**版本升為 `1.2.0 (4)`；`Distribution/Anchora-1.2.0-macos-arm64.zip`（8.5 MB）已產出並通過 ad-hoc 簽章驗證。**

**README**：補上 macOS 14.0 最低需求、更新建置需求說明、更新 release asset 檔名與 SHA-256、新增執行測試的說明。

使用者已實測真實 API 請求：串流、回應與 Pin 流程皆正常。

### 13:10–14:00 — Markdown 回覆渲染

回覆改為要求並渲染 Markdown。

**為什麼需要自己切 block。** SwiftUI 的 `AttributedString(markdown:)` 只理解**行內**語法。`## 標題`、`- 條列`、程式碼區塊會被解析成 presentation intent，而 `Text` 直接把它丟掉 — 也就是說 `- item` 會渲染成沒有項目符號的一行字。因此新增 `AnchoraMarkdown` 先把回答切成 block（段落、標題、有序／無序條列與其縮排層級、引言、程式碼區塊、分隔線），只把行內範圍交給 `AttributedString`；`AnchoraMarkdownText` 再逐一排版。

**block id 是位置而不是每次解析新產生的 UUID。** 串流時每次 flush 都會重新解析整份回答；若用 `UUID()`，SwiftUI 每秒會拆掉重建全部 block（一份 paper map 約 112 個）八次，而且讀者正在進行的文字選取會被中斷。實測完整重新解析一份 7.6 KB 的回答約 1.9 ms，因此不需要快取，只需要穩定的身分。

**Prompt。** system instructions 加入格式規則，並且刻意寫明限制的原因：不得整份包在 code fence（會渲染成一整塊灰底）、不得使用 Markdown 表格（renderer 沒有表格 block）、`[PDF p. X]` 必須維持字面形式（Paper Map 之後要靠它解析，且不能被當成 Markdown 連結）。同時要求結構與長度相稱 — 一兩句話的回答就是一個段落，不加標題也不加條列。

**Pin 回 PDF 會先攤平 Markdown。** PDF 註記是純文字，且要在其他 PDF app 裡也讀得下去，所以 `AnchoraMarkdown.plainText(from:)` 會把粗體、反引號與標題標記去掉，條列轉成 `• `、引言轉成引號。

**渲染時抓到並修掉的四個問題：**

- 標題沒有變大變粗：`inlineText` 內層的 `.font` 蓋過外層的標題字體，所有 block 都以本文大小渲染。字體改為由各 block 決定。
- `` `code` `` 沒有樣式：`Text` 會自動處理粗體、斜體與連結，但 code 只帶 presentation intent。現在逐一走訪 run，替 code 範圍套上等寬字體。
- `Web sources` 被當成 Markdown：那是我們自己組的字串不是模型輸出，兩行網址被 parser 併成一個段落。已排除在 Markdown 渲染之外（使用者訊息與請求階段的 placeholder 同樣排除）。
- 條列項目沒有撐滿可用寬度。

**測試增加到 94 個檢查**：block 種類辨識、巢狀縮排、串流中的半成品語法（未閉合的 fence 與粗體）、block id 穩定性、citation 不被當成連結且切分後仍可解析、pin 用的純文字攤平，以及「格式規則與 renderer 能力一致」的檢查。

Paper Map 的段落內容維持既有的 evidence 標示與 Source quote 連結渲染，未套用 Markdown — 那裡的語意標示比粗體斜體更有價值，而且兩者的範圍計算會互相干擾。

### 14:00–15:40 — turn state、擷取層與 composer 全面 Swift 化

一次處理三件互相牽動的事，順序是「產生值 → 持有值 → 顯示值」。

#### H：OCR、頁面渲染與圖像擷取移出 view controller

- 新增 `AnchoraCapture`（PDFKit + Vision）：區域圖像、整頁圖像、以及區域文字辨識共用同一個 render 路徑。原本三處各自重複的 bitmap 建立、白底填色、縮放平移、4096px 上限現在只有一份。
- 保留「渲染 PDF 內容而非截取 view」的原因註解 — 截圖會包含 Skim 的選取暗化覆蓋層，正好會讓這功能主要服務的大面積投影片區域辨識失準。
- 新增 `AnchoraTextQuality`：判斷 PDF 文字層可不可信的純算術，可獨立測試。實際的 private-use-plane 字元掃描仍交給 Skim 的 `stringByRemovingAliens` — 那是一個仔細寫過的 workaround，不該重寫。
- Vision 改用 `Task.detached` + `MainActor.run`，取代 `dispatch_async` 與手動 `CGImageRetain`／`CGImageRelease`。
- `recognizeTextForCurrentSelection:generation:`、`recognizeTextInPageRect:`、`finishOCRWithText:` 三個方法收成一個。

#### G：16 個平行 property 收成兩個 value type

- `AnchoraSelection`：讀者當下的選取。不可變，每次轉換都是一個具名的 factory（`empty` / `text` / `recognizing` / `image` / `byFinishingRecognition`），CONTEXT 卡片要顯示的字串就放在產生該狀態的地方。
- `AnchoraTurn`：送出請求當下拍的快照。問題、context 文字、選取／頁面錨點、來源頁碼、是否為 paper map、目前階段、累積的回覆。
- 兩者分開正是重點：讀者會在回覆串流期間繼續閱讀與選取，而 Pin 必須把答案錨回它真正被問的那段內容。
- generation 計數移進 `AnchoraSelection`；`byFinishingRecognition` 刻意**沿用**同一個 generation，因為那個結果仍然屬於讀者當初做的那次選取。
- `hasCharacters` 由呼叫端傳入而不在 value type 內重算：那是 Skim 針對 PDFKit 的 workaround（一個 selection 可能宣稱有頁面卻沒有任何 text range），不該重寫，而且這樣 value type 就沒有 Skim 依賴、可以進測試。

#### I：composer 與快捷列改為 SwiftUI

- 快捷列與輸入列合併成單一 `AnchoraComposerView`，由 `AnchoraComposerModel` 驅動。view controller 不再建立或量測任何一個控制項。
- 這一列正是側欄最嚴重那個 bug 的所在：用 `NSStackView` arranged subview 組出來，會讓 AppKit 在側欄還在安裝時就去問 fitting size，開檔時的量測迴圈可以吃掉數十 GB。等寬按鈕是框架可以直接表達的排版。
- 等寬要套在 button 的 **label** 上：只放大 button 的 frame，bezel 仍會停在標題的自然寬度並置中（第一次渲染就是這個結果）。
- composer 由 host 給固定高度而非回報 intrinsic size。裡面沒有任何會換行的東西，高度本來就不該取決於寬度；用固定高度是把這個保證寫進排版，而不是寄望於內容不變。
- 快捷按鈕的 tooltip 移進 `AnchoraPrompts`，每個動作都有自己的說明，不再只是重複標題。

#### 結果

- `SKRightSideViewController.m`：1,508 → **1,249 行**（整個重構累計 2,256 → 1,249，少了 45%）。
- 該檔的 `@property` 由 30 個降到 16 個，其中 AI 狀態只剩 `aiSelection`、`aiTurn`、`aiClient`、`aiConversation`、`webVerificationEnabled`。
- Swift 檔案 17 個；測試 124 個檢查。
- Debug／Release 建置成功、Anchora 程式碼警告 0、實跑 200 MB 無 constraint 衝突。
- 實機確認：Study／Scientific 切換會重建快捷列與標題、三個與六個按鈕都等寬填滿窄側欄、Send 的提示去重、Clear chat 清空並停用 Pin、Web verify 可切換。串流與真實 API 路徑未在此輪重跑。

### 15:40–16:10 — 補上 Ask AI 的焦點，並封裝 1.3.0

- `Ask AI`（選取後浮出的動作列）重新取得把游標放進輸入框的行為。SwiftUI 的 `TextField` 沒有可以從 Objective-C 直接 `makeFirstResponder:` 的對象，因此改由 `AnchoraComposerModel` 的 `focusQuestionField` 送出請求，view 以 `@FocusState` 接收。用計數器而不是布林值，這樣連續兩次請求都會生效，即使欄位已經取得過焦點。
- 焦點在隔離的 harness 中驗證（使用者自己的 Xcode instance 當時開著真實 PDF，用 bundle identifier 驅動有可能動到那份文件）：`focusQuestionField` 之後 first responder 為 SwiftUI 的 field editor，截圖也看得到游標。
- 版本升為 `1.3.0 (5)`。
- 封裝：`xattr -cr` 清除延伸屬性後 ad-hoc 重簽，`codesign --verify --deep --strict` 通過。解壓後的副本再次驗簽並實際啟動，約 198 MB、無 constraint 衝突。

## 發行內容（1.3.0）

- Swift 核心層：settings、keychain、prompts、paper map、Responses 串流 client、Markdown、擷取層、turn state。
- SwiftUI 側欄：聊天紀錄、Paper Map navigator、快捷列與輸入列。
- Markdown 回覆渲染；Pin 回 PDF 時攤平為純文字。
- 修正三個既有 bug：Paper map 的 Limitations 段落從未被切出、Hide 之後無法叫回 Paper Map、以及新串流 client 的 data race。
- 最低系統版本 macOS 14.0；Apple Silicon。

### 1.3.1 — 修正 Option／Command-Option 拖曳完全失效

使用者回報 `Command + Option + 拖曳` 之後圖像沒有被載入對話。

- **根因是本次重構的 regression。** 在把 turn state 收成 value type 那一輪重寫 `updateSelectionContext:` 時，方法開頭的通知分派整段被刪掉了。`SKPDFViewAISelectionAreaChangedNotification` 與 `SKPDFViewAIImageSelectionAreaChangedNotification` 的 observer 一直都有註冊，但收到之後沒有被導向 `captureAISelectionArea` 與 `captureAIImageSelectionArea`，所以兩個方法都變成沒有任何呼叫端。
- 因此壞掉的**不只圖像擷取**：`Option + 拖曳` 的區域 OCR 同樣完全失效，只是比較不容易被注意到。
- 一併還原被刪掉的守衛：矩形拖曳在追蹤期間也會送出一般的選取通知，必須等它自己的最終通知，否則每一次滑鼠移動都會清掉前一次的 context。
- 加上「定義了卻沒有任何呼叫端」的結構檢查，這正是能抓到這類遺漏的方式。該檢查另外找出三個因為搬到 Swift 而成為孤兒的方法（`conversationInputItems`、`paperMapPageIndexesForText`、`replaceStreamingPlaceholderWithText:`），已移除。`handleSnapshotViewFrameChanged` 同樣沒有呼叫端，但它在 1.1.0 之前就是如此，屬於 upstream Skim 的遺留，未動。

`SKRightSideViewController.m` 為 1,251 行。版本 `1.3.1 (6)`。

### 1.3.2 — OCR 認不出中文

使用者回報 OCR 對中文完全無效，英文也像只抓到片段。

- **根因：`VNRecognizeTextRequest` 沒有設定 `recognitionLanguages`，預設只認英文。** 這是既有問題（1.1.0 的 Objective-C 版本同樣沒設，移植時原樣保留了），不是本次重構造成的。
- 以離線測試證實：對一段中文區域，修正前 Vision 回傳 `nil`（完全沒有結果），設定 `["zh-Hant", "zh-Hans", "en-US"]` 之後正確辨識，英文區域不受影響。這台機器的 accurate 模式支援 30 種語言，含 `zh-Hant` 與 `zh-Hans`。
- 語言清單會與 `supportedRecognitionLanguages()` 取交集後才送出，因此不支援的語言只會被略過而不會讓整個請求失敗；清單為空時退回 `en-US`。這段解析邏輯抽成 `AnchoraTextQuality.resolveRecognitionLanguages`，可獨立測試。

**一併查證但未修改的兩項：**

- **區域擷取是正確的。** 建了一份四個象限各有已知文字的 PDF，對右上象限做區域擷取，渲染尺寸與請求完全相符，辨識結果只有該象限的文字。截圖中出現框外文字是前一次較大範圍拖曳留下的 CONTEXT，不是擷取錯誤。
- **CONTEXT 卡片會正常換行。** 以 app 真實的 Auto Layout 條件重現（zero-frame `NSTextView`、卡片高度 86pt），文字在 302pt 內排成四行，沒有溢出。截圖中只有一行是因為 Vision 當時真的只認出那麼多。
- **渲染倍率維持 2x。** 用 9pt 小字測 1x／2x／3x／4x：1x 平均信心 0.60 且有錯字，2x 為 0.83 且文字全對，3x 與 4x 沒有任何改善。提高倍率只會增加成本。

版本 `1.3.2 (7)`；測試 128 個檢查。

---

## 目前可用功能

### PDF 與筆記

- Text Tool、Highlight、Text Note、Box Note 快速工具列。
- Text Note 為頁面上可直接看見、可拖曳與可編輯的便利貼。
- AI anchor note 可保存、重開、拖動與刪除。
- 用其他 PDF app 開啟時仍保留標準 PDF annotation；在 Anchora／Skim 中可繼續編輯。

### AI 對話

- 選取文字後提問。
- OCR 區域與圖片區域輸入。
- `Study`／`Scientific` 閱讀 profile；Study 提供 Explain、Translate、Clinical，Scientific 提供 Paper、Question、Hypothesis、Methods、Figure、Evidence。
- 全域繁體中文／English 回覆語言設定。
- 可選擇的 Web verify 網路查證模式；回答後列出實際使用的網路來源。
- 本機短期對話記憶與 Clear chat。
- Pin 最新 AI 回覆回 PDF。
- 頁面影像摘要與整份 PDF 摘要。
- 完整論文 PDF 的 Paper map、圖表／軸線解釋與證據／限制拆解。

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
| 論文閱讀 | Scientific profile + whole-PDF input | 讓高層問題、方法、圖表、證據與限制可從整篇論文重建，而非只依一小段反白文字。 |
| 回覆渲染 | 明確 bubble 文字高度與來源 footer constraints | 避免 AppKit 的 intrinsic-size 推算造成空白、截斷或 source link 重疊。 |
| 穩定性 | 不使用 `NSStackView` arranged-subview/fitting-size 建立快捷列 | 避免 PDF 開檔時的 layout 量測迴圈與不受控記憶體成長。 |
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
- Release 附件：`Distribution/Anchora-1.3.2-macos-arm64.zip`（8.6 MB）
- 版本：`1.3.2 (7)`
- 最低系統：macOS 14.0
- 大小：約 17 MB
- Bundle ID：`com.kris.anchora`

## 後續候選項目（尚未實作）

- AI 回覆的 `Copy`、`Pin as anchor`、`Pin as text note` 行動列。
- 以「主題 → 頁碼」呈現的 PDF 學習地圖。
- Paper Map 段落內容的 Markdown 渲染（需與既有的 evidence／quote 範圍標示整合）。
- Markdown 表格支援。
- 使用 Developer ID 簽章與 notarization，支援正式對外散布。
