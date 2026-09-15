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

### 1.3.3 — 擷取區域被頁面 box 原點平移

使用者框選投影片中間的一段文字，CONTEXT 卻顯示投影片標題（在框外）。上一輪我把類似現象判斷為「前一次拖曳殘留」，那是錯的。

- **根因：`page.draw(with:to:)` 會把顯示 box 的原點移到 context 原點**，因此頁面上的點 `p` 會被畫在 `p - bounds.origin`。而 view 回報的選取矩形是頁面自身座標、仍帶著那個原點，所以平移時必須一併扣掉。原本只有 `-rect.minX / -rect.minY`。
- 頁面 box 原點為 (0,0) 時兩者等價 — 這正是先前的測試沒抓到的原因，我用的測試 PDF 原點就是 (0,0)。簡報匯出的 PDF 則經常不是。
- 以原點 (50, 30) 的 PDF 驗證：修正前框選中段讀到 `OLE BRAVO the target`（被平移並切掉開頭），修正後為 `MIDDLE BRAVO the target`；標題區域、中段區域、整頁三種情況現在都正確。
- **影響範圍不只 OCR。** 同一個 render 路徑也供 `Command + Option` 圖像擷取與整頁摘要使用，因此在這類 PDF 上送給模型的圖片同樣是偏移的。整頁擷取原本會被平移兩次（`rect` 與 `bounds` 各扣一次原點）。
- 平移計算抽成 `AnchoraCapture.renderTranslation(for:pageBounds:)`，加上三個回歸測試：原點偏移的頁面、整頁擷取（平移應為零）、原點本來就是零的頁面。

版本 `1.3.3 (8)`；測試 131 個檢查。

### 1.3.4 — 擷取區域沒有考慮頁面旋轉

1.3.3 修的 box 原點只是問題的一半，使用者提供的三張截圖給出了決定性線索。

**診斷。** 比對 Skim 狀態列回報的選取尺寸與截圖中可見的選取框：三張全部要把**寬高對調**才吻合（230×327 對 1.40、192×395 對 2.04、121×568 對 4.47）。那是頁面旋轉的特徵。

**根因。** `SKPDFView` 以 `convertPoint:toPage:` 儲存選取矩形，那是 PDFKit 的**未旋轉**頁面座標；`page.bounds(for:)` 同樣回傳未旋轉尺寸（旋轉 90° 的頁面仍回報 600×800）。但 `page.draw(with:to:)` **會**套用旋轉。因此繪製輸出在旋轉後的空間，而矩形與 bounds 在未旋轉空間，兩者不一致。

**驗證。** 以四種旋轉、三個在 x 軸刻意不對稱的目標（好讓「旋轉」與「單純轉置」給出不同答案）做端到端測試：套用旋轉轉換後 12/12 全部正確，單純轉置則錯得五花八門。另外用使用者截圖 3 的實際數字驗算：回報的 `121 × 568 @ (383, 177)` 經 90° 轉換後落在頁面 x 22%–94%、y 63%–82%，與可見選取框的 20%–98%、62%–83% 相符。

**修正。** `AnchoraCapture.renderRect(for:pageBounds:rotation:)` 一次處理兩件事 —— 扣掉 box 原點，並依 0／90／180／270 映射矩形；旋轉四分之一圈時畫布長寬也隨之對調。1.3.3 的 `renderTranslation` 被它取代。加了七個回歸測試涵蓋四種旋轉、超過一圈與負角度的正規化、原點偏移，以及旋轉頁面的整頁擷取。

**影響範圍同 1.3.3**：OCR、`Command + Option` 圖像擷取、整頁摘要與 Scientific 的 `Figure` 共用這條路徑。使用者回報 `Command + Option` 當時看起來正常 —— 兩者用的是同一段程式碼與同一個矩形，所以那份圖其實同樣是偏移的，只是偏移後的畫面仍像一張投影片，不容易察覺。

版本 `1.3.4 (9)`；測試 138 個檢查。

### 1.4.0 — 每則回答的行動列，以及標題／CONTEXT 改為 SwiftUI

#### 回答行動列

- 每則答案下方有 `Copy`、`Pin as note`、`Pin as text`。
- **答案自己帶著它的 turn。** `AnchoraChatMessage` 新增 `turn` 欄位，因此三個問題之後回頭 pin 較早的那則答案，它仍然錨在當初被問的那段內容上，而不是最新的選取。原本的 `Pin latest answer` 只能處理最新一則。
- `Pin as text` 是新的路徑：`SKPDFView.addAITextNoteWithString:title:nearRect:onPage:` 建立可見於頁面上的 FreeText 註記，尺寸用 Skim 自己的 `SKFitTextNoteSize` 依文字計算，並沿用使用者設定的字型與預設寬度；旋轉的頁面會對調長寬。優先放在錨點右側，放不下才改放左側。
- `Copy` 放上剪貼簿的是**攤平後的純文字**，與 pin 一致 —— 貼進筆記或信件時不該出現 Markdown 標點。
- 最新一則答案的行動列常駐顯示，較舊的 hover 才出現。全部隱藏的話沒有人會發現它存在；全部常駐則會讓以閱讀為主的對話變得吵雜。
- 保留 composer 的 `Pin latest answer`：它是既有且每天在用的路徑，新的行動列是補充而不是取代。

#### 標題列與 CONTEXT 卡片改為 SwiftUI

- 新增 `AnchoraHeaderModel` 與 `AnchoraHeaderView`，涵蓋標題、副標、Study／Scientific 切換、`•••` 按鈕與 CONTEXT 卡片。
- 移除 `scrollViewWithTextView:` 與 `aiCardView` —— AI 側欄不再有手工組裝的 AppKit 卡片。
- `•••` 選單**仍然是 NSMenu**：它會統計文件的註記數量並顯示註記顏色，那是 Skim 的世界而不是 Anchora 的。SwiftUI 按鈕只回呼，由 view controller 把選單彈在標題列的右上角。
- 高度同樣固定而非回報 intrinsic size，理由與 composer 相同。

#### 新工具：孤兒方法檢查

`Tools/find-orphaned-methods.py` 列出「有定義但沒有任何呼叫端」的 Objective-C 方法。這正是 1.3.1 那個 regression 的特徵 —— 通知分派被刪掉後，兩個 capture 方法變成無人呼叫，程式照樣編譯、observer 照樣註冊，功能卻消失了。

第一版有前綴誤判（`showAIMoreActionsFromHeader` 蓋到 `showAIMoreActions`），已修正邊界判斷。`handleSnapshotViewFrameChanged` 列在已知的 upstream 例外清單裡：它在 Anchora 開始之前就沒有呼叫端，屬於 Skim 的程式碼，不刪除。

#### 結果

`SKRightSideViewController.m` 1,251 → **1,203 行**；測試 144 個檢查。版本 `1.4.0 (10)`。

Release 建置 0 錯誤。`SKPDFView.m` 有 23 個警告，全部是 Skim 既有的（廢棄 API、可用性、縮排），沒有一個落在本次新增的 2818–2854 行。

### 1.4.1 — `•••` 選單彈錯位置

使用者回報選單出現在 CONTEXT 卡片下方，而不是按鈕下方。

**兩個疊在一起的錯誤。**

1. **座標系翻轉。** `NSHostingView.isFlipped` 是 `true`（y 由上往下），一般 `NSView` 則是 `false`。我用 `NSHeight(bounds) - 24` 當作「靠近頂端」，在翻轉的視圖裡那是靠近底端。
2. **`PreferenceKey.reduce` 寫錯。** 改用 SwiftUI 回報按鈕實際位置之後仍然拿不到值：`value = nextValue()` 會讓後面的兄弟節點（CONTEXT 卡片）用預設值把按鈕回報的 frame 蓋掉。harness 印出 `GEOM (640, 0, 36, 20)` 但 `PREF (0, 0, 0, 0)`，兩行就定位了問題。`reduce` 改成只在非預設值時覆寫。

**修正後**：SwiftUI 透過 preference 回報 `•••` 的實際 frame，選單位置的換算移到 `AnchoraHeaderModel.moreActionsMenuLocation(inViewBounds:isFlipped:)` —— 從 Objective-C 的呼叫端搬進 Swift，因為那是一段有兩種座標系的幾何計算，應該被測試而不是被猜。

五個新測試涵蓋：翻轉與未翻轉的 fallback 角落、翻轉與未翻轉的按鈕下方位置（同一個點在兩種座標系下 y 不同），以及結果確實落在按鈕所在的右上象限。

版本 `1.4.1 (11)`；測試 149 個檢查。

### 1.4.2 — 中文旁的粗體渲染不出來

`**橫膈膜 (diaphragm)**收縮時` 顯示成字面的星號。

**根因是 CommonMark 的 flanking 規則。** 收尾的 `**` 前面是標點 `)`、後面是漢字：依規則，被標點包圍且後面不是空白或標點的分隔符不具備「可結束」資格，因此整段當作字面文字。中文寫作幾乎不會在粗體後面加空白，所以只要是「粗體 + 中文」就會踩到。GitHub 在 2017 年為 CJK 放寬了這條，CommonMark 至今沒有，而 `AttributedString(markdown:)` 走的是嚴格規則。

**修正方式是自己解析行內語法**，不再使用 `AttributedString(markdown:)`。放寬後的規則是：分隔符後面不是空白就可以開始，前面不是空白就可以結束。涵蓋粗體、斜體、行內 code、連結與裸露的 http(s) 網址；反斜線跳脫、未閉合的分隔符（串流途中必然出現）維持字面輸出。

保留的既有行為：`snake_case` 不是斜體、`2 * 3 * 4` 不是強調、`[PDF p. 4]` 後面沒有括號就不是連結（Paper Map 之後還要靠它解析）。

24 個新測試，包含中文相鄰的粗體與斜體、巢狀強調、串流途中的半成品語法、citation 不被吃掉，以及裸露網址仍可點擊。

版本 `1.4.2 (12)`；測試 173 個檢查。

### 發布流程與散布方式

想讓幾位同學也能安裝，先釐清 quarantine 實際上是怎麼運作的。

**實測結果（macOS 26.6.2）：**

- 剛解壓的 app 沒有 quarantine 屬性；`spctl` 判定為 `rejected`，因為 ad-hoc 簽章不是 Developer ID。
- 手動加上 `com.apple.quarantine`（模擬瀏覽器下載）後，`spctl` 仍是 `rejected`。
- 移除該屬性後，簽章依然有效。

關鍵在於：**擋下 app 的是 quarantine 旗標，不是簽章本身。** ad-hoc 簽章的 app 只要沒有 quarantine 就能正常啟動。而 macOS 15 之後，「右鍵 → 打開」已經不再是繞過 quarantine 的途徑，使用者必須進「系統設定 → 隱私權與安全性」。

本機沒有任何 codesigning 身分（`security find-identity` 回報 0 個），因此 Developer ID 這條路目前無法進行。

**新增 `Tools/package-release.sh`。** 一個指令完成：跑測試與孤兒方法檢查 → Release 建置 → 清除延伸屬性 → **由內而外**簽章（巢狀的 Sparkle.framework、其中的 Updater.app、SkimNotes.framework、Spotlight importer 及其內部 framework）→ 打包 → 輸出版本與 SHA-256。

設定 `ANCHORA_SIGN_IDENTITY` 與 `ANCHORA_NOTARY_PROFILE` 之後，同一個指令會改用 hardened runtime 與 secure timestamp 簽章、送交公證、staple 票證並重新打包。**這條路尚未實際跑過**，因為沒有憑證可用；README 已註明第一次公證很可能需要調整 entitlements，因為 bundle 內嵌了 Sparkle、Updater、SkimNotes 與 Spotlight importer，每一個都必須滿足 hardened runtime。

改用由內而外簽章之後 zip 的內容有變，SHA-256 隨之更新為 `24656c0e…`。重新解壓驗簽並實際啟動確認無誤。

**README 的安裝說明改寫**為兩條路徑：一行 Terminal 指令（下載、安裝、清除 quarantine），以及 Finder + 系統設定的手動流程。前者明確說明它清除的是什麼、以及為什麼只該對信任的來源這樣做。

### 1.5.0 — Study map

拿到一份教材時想知道「該怎麼讀才有效率」，所以 Study 模式多了一顆按鈕，讓模型分析整份 PDF 並設計讀法。

**它產生的是計畫而不是摘要。** prompt 先要求模型判斷這是什麼性質的教材、讀完之後應該要會做什麼，再依「什麼相依於什麼」而不是頁面先後排出 5–10 個區塊，每塊給：涵蓋頁碼（以 `[PDF p. X]` 形式，才能跳頁）、讀完要能做到什麼、必須掌握的術語、這幾頁**該怎麼處理**（精讀／略過／重畫圖／背／做題），以及這裡常見的誤解。最後兩節分別是「時間不夠時的最短路徑」與「事後應該能默答的問題」。

**按鈕而不是選單項目。** 與 Scientific 的 `Paper` 對稱：Study 的快捷列變成四顆，`Study map` 排第一，不需要反白選取、直接分析整份文件。其餘三顆維持針對選取內容。

**Navigator 一般化。** 原本的 Paper Map navigator 形狀正好相同（選一節 → 讀 → 跳頁），差別只在解析規則：Paper Map 綁死八個英文標題，Study map 的區塊數不固定、標題還是使用者選的語言。因此：

- `AnchoraPaperMapSection` → `AnchoraMapSection`，獨立成一個 Foundation-only 的檔案；`AnchoraPaperMapModel`／`View` → `AnchoraMapModel`／`AnchoraMapView`。解析器 `AnchoraPaperMap` 維持原名，因為它確實只解析 paper map。
- 新增 `AnchoraStudyMap`：切在任何層級的標題上，保留模型給的順序（那個順序就是答案），標題去掉 Markdown 裝飾但保留編號。
- Model 依 `AnchoraMapKind` 自行決定卡片標題、說明文字與**內容如何渲染**：study map 用 Markdown 渲染，paper map 維持既有的 evidence 標示與 Source quote 連結 —— 後者的範圍是對原始文字算出來的，重排之後會失效。

**判斷是哪種 map 不再靠猜字串。** 原本用 `displayQuestion` 裡有沒有「Paper Map」字樣來判斷；現在由讀者按下的動作直接決定，`AnchoraTurn` 帶 `mapKind`。輸出 token 上限也改為「是 map 就給 16,000」，不再綁在 Scientific profile 上。

21 個新測試：任意標題的切分、裝飾標題轉純文字、沒有標題時的 fallback、Study profile 的四個動作與 tag 位移後各自仍對應正確的 prompt，以及 prompt 本身確實要求計畫而非摘要。

版本 `1.5.0 (13)`；測試 194 個檢查。

### 1.6.0 — 回饋迴圈：Recall 與 Quiz

讀完一頁不會產生任何「讀懂了沒有」的訊號，所以這一版加的兩個動作都只為了製造那個訊號：自己說一遍，或者被問。

**Recall 是 diff，不是摘要。** 讀者先在輸入列憑記憶寫一兩句，再按 `Recall`；模型拿整頁影像對照，只回報差異，分成「對的」「錯的」「漏的」與「先補哪一個」四段。prompt 明講 **judge the idea, not the wording** —— 觀念對但講得鬆散算對，句子漂亮但機制講反不算對 —— 並且禁止先講好話、禁止把第二段講軟。輸入列是空的就不送出，改在對話裡說明為什麼一定要先寫：沒有先寫，這個比對就沒有任何意義。transcript 裡的「問題」就是讀者自己那句話，糾正接在它下面，那個配對本身就是回饋。

**Quiz 只出題，不附答案。** 按下去模型針對當頁出 2–3 題然後停住，prompt 禁止它自問自答或給提示，並且明確要求考「能不能用」而不是「記不記得字面」：優先考套用到具體情境、區辨兩個相似的東西、預測條件改變後會怎樣、說明為什麼。**答案可以從頁面上抄下來的題目一律不算題目**，考版面、考在第幾張投影片的也不算。

出完題之後 composer 進入待答狀態：placeholder 改成 `Type your answers here, then Send…`，下一次 Send 不再是提問而是交卷。批改會**重新附上出題時的那一頁**，而不是靠模型對自己剛才問了什麼的記憶 —— 因此 `aiQuizPage` 跟著旗標一起存，讀者在作答前捲到別頁也不會改到批改的依據。頁面 render 失敗時 `analyzePage:` 回 `NO`，待答狀態就不會進入。Clear chat 與切換 profile 都會清掉它。

**快捷列砍到三顆，其餘下放 •••。** 原本 Study 四顆、Scientific 六顆，一排六顆按鈕等於沒有人會讀。分法是：**快捷列只放讀每一頁都會按的東西**，整份文件的計畫、一份文件只做一次的問題、偶爾才用的鏡頭，全部進 •••。

- Study 列：`Explain` / `Recall` / `Quiz` —— 由左到右就是使用順序。`Study map`、`Translate`、`Clinical` 進 •••。
- Scientific 列：`Methods` / `Figure` / `Evidence`。`Question` 與 `Hypothesis` 是一篇論文只問一次的整體問題（本來在沒有選取時就走整份文件路徑），進 •••。
- `Paper` 直接刪掉：••• 的「Build Paper Map (PDF)」本來就是同一個 prompt，這個重複正是把列撐到六顆的原因。因此 `overflowActions` 刻意不含 paper map，測試也把這件事釘住。

**動作不再用列上的 index 當身分。** 動作現在同時住在快捷列和選單兩個地方，再用 tag 分派的話，選單項的意義會被「列上剛好有幾顆按鈕」決定 —— 之前那組「tag 位移後各自仍對應正確 prompt」的測試就是這個設計在報警。改成 file-scope 的 `AnchoraQuickAction` 列舉，每個動作自己帶 title／menu title／display title／tooltip／prompt／scope／mapKind；`AnchoraActionScope` 說明它需要眼前有什麼（selection／page／document），view controller 就照 scope 分派而不是照 index。

順帶把兩件重複收掉：`analyzeCurrentPageWithQuestion:` 裡硬寫的三個字串換成 `AnchoraPrompts` 既有的常數，並且一般化成 `analyzePage:question:displayQuestion:`（Recall 與批改都要指定頁而不是「目前那頁」）；`askAI:` 裡的選取檢查與送出抽成 `askAIAboutSelectionWithQuestion:displayQuestion:`，快捷動作因此可以送出完整指令卻在 transcript 上只顯示短標題 —— 以前 Study 的快捷動作是把整段 prompt 塞進輸入列再送，使用者的氣泡裡就是那一整段。

Study 的歡迎訊息改成描述這個迴圈，否則兩顆新按鈕沒有任何地方解釋自己。

85 個新檢查（194 → 279）：每個動作在「列 + •••」裡剛好出現一次（在兩邊都沒有的動作等於按不到）、越界的列 index 不會誤觸別的動作、每個 scope 與 mapKind 的對應、Quiz 不自答也不考字面、批改帶得到作答內容且不准把錯講軟、Recall 帶得到讀者那句話且是比對而非摘要。

**尚未在畫面上實際操作驗證。** Release 建置與簽章通過、孤兒方法檢查通過、279 個檢查通過，但按鈕列與 ••• 的實際外觀、以及一次完整的 Quiz→作答→批改來回還沒跑過（會真的花 API 費用）。打包時 `/Applications` 裡的 1.5.0 正在執行，同 bundle ID 不宜再開一份，因此新版沒有在這台機器上啟動過。

另外把既有 prompt 裡的空白修掉：`formattingInstructions` 與 `studyMapPrompt` 有五行是先前編輯把 `\` 續行吃掉、兩行黏起來留下的長串空白。重新斷行後以兩個版本各自編譯、印出字串比對，**正規化空白後完全相同**，只少了 80 bytes 的多餘空格。

版本 `1.6.0 (14)`；測試 279 個檢查。

### 1.7.0 — Store、雜念收納，以及把 map 拉開

三件事其實是同一件：Anchora 到目前為止唯一留得住的東西是 PDF annotation，**剩下的全部活在記憶體裡**。所以這一版先做儲存，再把兩個一直被那個限制壓住的東西放開。

**`AnchoraStore`：Application Support 底下的 JSON，原子寫入。** annotation 該留在 PDF 裡（別的 app 讀得到，這也是 Pin 寫標準 annotation 而不是私有格式的原因），但**讀書計畫是關於文件、卻不屬於文件**，而讀到一半冒出來的雜念根本跟文件無關 —— 這兩種東西沒有地方去。inbox 一個檔，每份文件一個檔。

文件用**路徑**而不是內容雜湊當 key：Anchora 會改寫它讀的 PDF（存一個 highlight 就換掉了位元組），內容雜湊會讓剛建好的 map 當場變孤兒。代價是搬動檔案會失去該份 map；每筆紀錄旁邊存了 bookmark，就是為了之後能修好這件事而不必做資料遷移。

**雜念收納。** 一個輸入框、一個清單，沒有專案、沒有到期日、沒有標籤 —— 那些都是「寫下來的當下要做的決定」，而寫下來的當下正是閱讀被打斷的那一刻。中斷真正貴的部分不是打字，是**離開**。

- **⌘⇧J 從 app 任何地方叫出一個浮動視窗**，寫一行、Return 存檔關閉、Escape 丟掉。用 local event monitor 而不是選單項：選單項要動到一個翻成十種語言的 nib，而系統層級的全域熱鍵要 Input Monitoring 權限 —— 這個 app 沒有別的理由去要那個權限，而且公證流程本來就還沒跑通。local monitor 只看得到 Anchora 自己的鍵盤事件，不需要任何授權。
- 每則筆記記下**當時人在哪**（文件與頁碼），只在寫下的那一刻去問，所以沒有任何東西需要跟著捲動同步。一天之後「對照前面那張圖」沒有這個就毫無價值。
- 一份清單、多個視圖：每個開著的文件側欄各有一個抽屜，加上 ⌘⇧J 那個視窗。全部寫進同一個 store，各自發通知、其餘的重讀。
- 同一瞬間寫下的兩則（連按 ⌘⇧J 就長這樣）以寫入順序決定先後，清單不會在兩次讀取之間自己重排 —— 這是測試抓出來的。

**側欄的主體區變成可切換的三個面：`Chat | Map | Inbox`。** 原本 map 是擠在對話上方的卡片，248pt：讀一份讀書計畫太小，聊天時又佔太多，兩者永遠在搶同一塊側欄。它們本來就不是要同時看的東西 —— 導覽一份計畫跟問一個問題是兩種活動 —— 所以改成輪流，而且**每一面都拿到整個主體高度**。

沒有把 map 做成跟 `Study`／`Scientific` 並列的第三顆按鈕：那兩個是「用哪種方式讀」，map 是「產出來的東西」，並列會把兩種性質不同的東西擺在同一層。

副作用是一整套手算高度的程式碼消失了：`updateMapCardHeight`、`preferredHeight`、收合時那個 34pt 的殘留標題、隱藏時在 required 與 defaultHigh 之間切換的約束優先權，全部不再需要 —— 主體就是「被選中的那個 view」。`AnchoraMapModel` 也因此拿掉 `isExpanded`／`onLayoutChange`。

**Map 會被存下來。** 建一次 map 要上傳整份 PDF，重開文件時直接把上次那份叫回來，等在它的分頁後面而不是自動跳出去（剛按下去要的那份才會自動切過去）。同一份文件兩種 map 都建過的話，還原最近建的那一份。另外 **Clear chat 不再清掉 map** —— map 屬於文件、而且現在存得住，跟著對話一起清掉是錯的。

31 個新檢查（279 → 325）：空的 store 讀起來是空的而不是壞的、空白字串不會變成筆記、完成不等於刪除、清除只帶走已完成的、未知 id 不改變任何東西、每份文件各自保有自己的 map、空回應永遠不會覆蓋既有的 map、重建是取代而不是累加、路徑摘要穩定且不碰撞、兩個視圖看到同一份清單、內容消失的分頁不會繼續被選中。

**畫面上一樣還沒實際操作。** Release 建置與簽章通過、孤兒方法檢查通過、325 個檢查通過，但分頁列、兩個抽屜、⌘⇧J 那個浮動視窗都還沒被眼睛看過；打包時 `/Applications` 的舊版正在執行，同 bundle ID 不宜再開一份。

版本 `1.7.0 (15)`；測試 325 個檢查。

### 1.7.1 — 會長高的輸入框，以及縮成一行的 CONTEXT

**Return 送出，Shift-Return 換行，輸入框跟著內容往下長。** 交一份 quiz 的答案、寫一段憑記憶回想的內容，本來就該往下長而不是往右邊捲走。

SwiftUI 自己的多行 `TextField(axis: .vertical)` 做不到這件事：**不管有沒有按 Shift，Return 都送出**，所以根本沒有辦法打第二行。這是實測出來的，不是猜的 —— 寫了一個 harness 把 `AnchoraComposerView` 單獨跑起來（不需要 PDF、不需要 API key、不碰 Skim），用合成的鍵盤事件打字，然後印出 model 最後拿到什麼：

```
shift-return: question="ab"  submits=1   ← Shift-Return 直接送出，沒有換行
```

所以改成自己的 `AnchoraAskField`／`AnchoraAskTextView`：Return 與 Shift-Return 在 `keyDown` 裡明確分開判斷，而不是去賭 framework 對 field editor 的處理。換成 NSTextView 之後同一個 harness 給出的是：

```
shift-return: text=ab<NL>  field=24→40  total=84→94  submits=0
return:       text=ab<NL>c                            submits=1
long text:    field=108（上限）          total=162
cleared:      field=24                   total=84
```

**高度是回報的，不是 intrinsic 的。** 這個區別在這裡特別重要，因為側欄以前就被 intrinsic size 的協商弄垮過一次。現在是單向的：寬度由側欄給，高度往外送，host 拿去設約束 —— 沒有迴圈可以掉進去。約束優先權放在 required 之下，側欄很短時它會讓出來，而且超過約六行就改成捲動，不讓輸入框吃掉整個側欄。

過程中修掉兩個真的 bug：text container 少了 `autoresizingMask`／`minSize`／`maxSize`／`containerSize`，結果每一行都以無限寬度排版，打再多字量到的都是一行；以及 `textDidChange` 原本也把高度延後回報，打字會慢一行才長高 —— 打字是使用者事件而不是 view update pass，可以直接同步回報。

**CONTEXT 從 86pt 的卡片變成一行。** 那張卡片是整個側欄最貴的一塊，而它顯示的東西多半是你在旁邊 PDF 上已經反白看得到的文字。真正值得那個空間的是 **PDF 本身看不出來的狀態**：OCR 還在跑、抓了一塊區域當影像、整份 PDF 已附上 —— 而那些本來就各自只有一行。

需要看全文的時候（尤其是 OCR 的結果，送出去之前你會想確認它到底讀成什麼）點一下放大鏡，**用 popover 展開**而不是把 header 撐高 —— 這樣 header 維持固定高度，側欄只有一個會動的高度（輸入框）而不是兩個。只有「Anchora 抽取出來的文字」才可以展開，這件事由 `AnchoraSelection` 的每個 factory 自己宣告，不是靠猜字串。

header 從 146pt 降到 78pt，**還給主體 68pt**。

17 個新檢查（325 → 342）：夾限的上下界、NaN 與無限大不准進約束、清空欄位會縮回一行、換掉文字不會動到量到的高度、PDF 文字層的硬換行在摘要裡被收成一行、只有抽取出來的文字可以展開。

**畫面上仍然沒有在真的 app 裡看過。** harness 驗證的是輸入框本身的行為（按鍵、長高、縮回、上限），這部分現在是確定的；但它裝回側欄之後跟 header、分頁列、抽屜擠在一起是什麼樣子還沒看過。

版本 `1.7.1 (16)`；測試 342 個檢查。

### 1.7.2 — 啟動時不再是一片空白

沒有帶檔案啟動 Anchora，畫面上什麼都不會出現：沒有視窗、沒有面板，只有選單列和標題列變了。三個人因此卡住，所以這不是他們的問題。

**這是 Skim 上游的行為，而且是刻意的。** `applicationShouldOpenUntitledFile:` 永遠回傳 `NO`，因為 Skim 是閱讀器、不建立未命名文件，預期你從檔案啟動它。那個假設對第一次打開這個 app 的人不成立。同一片空白也發生在「Dock 圖示點一下但沒有任何視窗」的時候 —— 那條路最後也走到同一個 delegate。

改法是把「有沒有東西正在還原」跟「要不要提供開檔面板」拆開：`reopenPreviousSession` 從原本那段邏輯抽出來，回傳有沒有上一次的工作階段可還原；`applicationShouldOpenUntitledFile:` 在沒有的時候回傳 `YES`，`applicationOpenUntitledFile:` 叫出標準的開檔面板。

兩個細節：

- **面板是延後叫出來的。** 直接在 `applicationDidFinishLaunching` 裡跑面板會把啟動流程卡住 —— 包括版本更新時的 release notes —— 直到使用者選了檔案為止。
- **被問過而拒絕的還原也算「有工作階段」。** 剛按掉「確定要開 20 份文件嗎」的人，不會想接著看到一個開檔面板。

**這次是實際跑起來驗證的**，用 `CGWindowListCopyWindowInfo` 讀視窗清單（只要 bounds 不需要任何授權）：

| 啟動方式 | 結果 |
| --- | --- |
| 空白啟動、沒有可還原的工作階段 | `name=Open 880x448` 面板出現，且 release notes 同時也在 —— 確認沒有卡住啟動流程 |
| 帶著檔案啟動 | 只有文件視窗，沒有面板 |
| 空白啟動、還原開啟且有工作階段 | 文件還原，**沒有**面板 |

沒有新增自動化測試：這段是 app delegate 的啟動路徑，沒有可以單獨測的 Swift 介面。上面那三種情境是直接觀察行為驗證的，對這個改動來說比單元測試更有力。

沒有做成偏好設定。面板只在「完全空白的啟動」出現，從 Finder 雙擊 PDF 或還原工作階段都不會看到它。

版本 `1.7.2 (17)`；測試 342 個檢查。

### 1.7.3 — ⌘Q 不再靜悄悄地丟掉你的標註

按 ⌘Q 直接就走了，即使文件還有沒存的修改。這是**真正的資料遺失**，不是小瑕疵。

**先確認它真的會掉，而不是猜。** 造一份拋棄式 PDF、用 app 自己的 AppleScript 介面加一個 anchored note，`modified` 從 `false` 變 `true`，然後退出 —— 沒有任何詢問、程序消失、檔案還是原本的 390 bytes、裡面沒有 `Annot`、也沒有 `.skim` 旁檔。標註就是不見了。

**關掉文件會問，退出不會。** 同一份文件執行「關閉」時有一個 260×238 的儲存對話框跳出來，所以 `canCloseDocumentWithDelegate:` 這條路是好的 —— 壞的只有退出那一條。document-based app 本來就應該在離開時自動檢查未儲存的文件，這個 app 沒有，程式碼裡也找不到任何東西覆寫它（沒有 `applicationShouldTerminate:`、沒有 `NSTerminateNow`、`autosavesInPlace` 是 `NO`）。既然不能依賴，就明確地自己要求：`applicationShouldTerminate:` 呼叫 `reviewUnsavedDocumentsWithAlertTitle:` 並回傳 `NSTerminateLater`。

**過程中自己製造又修掉一個 bug，是測出來的。** 第一版在回呼裡直接 `replyToApplicationShouldTerminate:`，結果**沒有未儲存變更時整個 app 掛住不退出**：沒有東西要檢查的時候，那個回呼是**同步**執行的 —— 它跑在 `applicationShouldTerminate:` 裡面，也就是在它回傳 `NSTerminateLater` 之前。等於在問題被問出來之前就先回答，然後 app 就永遠在等一個已經來過的答案。把回覆丟到 main queue 的下一輪就解決了。

**取消退出要把狀態放回去。** `SKApplication` 在任何人被詢問之前就先廣播「開始終止」，而 `applicationStartsTerminating:` 已經把追蹤開啟文件的 observer 和 timer 拆掉了。在有 review 之前退出永遠不會被取消，所以這件事從來不重要；現在會了。因此把那段抽成 `startTrackingOpenDocuments`，取消時重新裝回去，否則這個 session 剩下的時間都會安靜地不再記錄哪些檔案開著。

四種情況都實際跑過驗證（用 `CGWindowListCopyWindowInfo` 讀視窗清單，不需要任何授權）：

| 情況 | 結果 |
| --- | --- |
| 沒有修改，直接退出 | 乾淨退出，不會卡住 |
| **有未儲存修改，退出** | **儲存對話框跳出，app 停在那裡等** |
| `quit saving yes` | 存檔（390 → 13,746 bytes，`Annot` 寫進去了）後退出 |
| `quit saving no` | 丟棄並乾淨退出，檔案維持原樣 |

**沒有驗到的：** 對話框上按「取消」之後 observer 有沒有正確裝回去。按按鈕需要輔助使用權限，那不值得為了這件事去要。這條路是推理出來的，不是觀察到的。

版本 `1.7.3 (18)`；測試 342 個檢查（這次沒有新增自動化測試：這是 app delegate 的終止路徑，沒有可以單獨測的 Swift 介面）。

### 1.7.4 — 輸入法組字中的 Return，以及追問之後不能 Pin

課堂上實際使用回報的兩個問題，兩個都確認過才修。

**打「為什麼RA與頸椎問題有關」，送出去的只有「為什麼RA」。** 這是 1.7.1 自訂輸入框帶進來的，而且比「截斷」更嚴重 —— 送出去的問題本身就是殘缺的，所以模型回答的是一個你沒問過的問題。

中文與日文輸入法用 **Return 來確認候選字**，但 `keyDown` 無條件把 Return 攔下來拿去送出，於是組字中（marked text）的那一段被整個丟掉，送出的是最後一次已確認的內容。在 harness 裡用 `setMarkedText` 重現得一模一樣：

```
composing: displayed=a與頸椎  marked=true  binding=a
after Return while composing: submits 1 -> 2, binding=a
```

修法是 `hasMarkedText()` 為真時不攔截，把 Return 交還給輸入法。修完之後同一個情境 `submits 1 -> 1`，而一般的 Return 送出與 Shift-Return 換行都不受影響。

harness 沒辦法假造真實輸入法的「確認」動作（它背後沒有真的組字 session），所以**被驗證的是「組字中不再送出」這件事**；確認之後文字正確落地要靠真的輸入法。

**追問之後 Pin latest answer 會變灰。** 不是偶發 —— 只要是**沒有重新選取文字**就問的問題都不能 pin，所以一段對話裡第一個問題之後幾乎都不能。

原因是 `AnchoraTurn.canPin` 要求有東西可以掛：`receivedOutput && (hasTextSelection || page != nil)`。追問走的 `AnchoraSelection.empty` 兩者都沒有，於是那個回答沒有任何可以附著的位置。

修法是追問時把**讀者當下所在的頁面**當作錨點交進去 —— 那就是他們問這個問題時人在的地方。有文字選取時 `AnchoraTurn` 本來就會忽略傳進來的 page（一個 turn 不會同時掛在選取與頁面上），所以這個 fallback 不會影響既有行為。

5 個新檢查（342 → 347）：掛在頁面上的已回答 turn 可以 pin、答案還沒到時仍然不行、掛在選取上的 turn 不會同時掛在頁面上而且照樣可以 pin。

版本 `1.7.4 (19)`；測試 347 個檢查。

### 1.8.0 — 用 iPhone 拍進來

在 PDF 上按右鍵，選單最後多了「Import from iPhone or iPad」—— 就是 Word 和備忘錄裡那個。拍一張講義、白板、或一頁不是 PDF 的書，照片直接變成 AI 的 context，側欄打開、游標落在輸入框，可以直接問。

**它跟既有的「Command-Option 拖曳一塊區域」是同一條路。** 問題本身沒有變 —— 「這個東西是什麼意思」—— 只是這次它從紙上開始。所以照片走的是同一個 `AnchoraSelection.image(...)`，錨定在讀者當下的頁面上（因此答案仍然可以 Pin：照片是文件旁邊的東西，但人還在文件裡）。

**Continuity Camera 沒有自己的 API，它走 Services 那套。** AppKit 沿著 responder chain 問「誰可以接收一張圖片」，只有在有人回答可以的時候才會提供裝置選單。所以實作是兩半：

- `validRequestorForSendType:returnType:` 加上**接收**方向。Skim 本來就實作了這個方法的**送出**方向（把選取內容交給 Service），所以是併進既有實作而不是另外寫一個 —— 第一次寫成獨立方法時編譯器直接報 duplicate declaration。
- `readSelectionFromPasteboard:` 收到圖片後發一個 notification，側欄接起來。

選單項本身只要把 identifier 設成 `NSMenuItemImportFromDeviceIdentifier`，AppKit 會自己換成附近的裝置與它們的 Take Photo／Scan Documents，沒有裝置時整項拿掉 —— 程式碼不需要知道桌上有什麼。

**刻意沒有加分隔線。** 沒有裝置時 AppKit 會把那一項移走，但它不會移走旁邊的分隔線；加了的話，每一台沒有 iPhone 在旁邊的 Mac 上，每一個右鍵選單底部都會多一條孤零零的線。

**照片會先縮小。** 手機給的是一千兩百萬像素，直接送又慢又貴，而且答得不會比較好；最長邊壓到 2048，JPEG 0.82。**但永遠不放大** —— 一張本來就小的照片放大只是多花錢。

11 個新檢查（347 → 358）：縮放比例只看最長邊、直的橫的一樣、已經小於上限的不動、正好在上限的不動、空圖不會除以零，以及完整的一輪 —— 4032×3024 進去，解回來是 2048×1536 的 JPEG。

其中一個檢查抓到我自己的錯誤假設：測試原本用 `NSImage(size:)` 加 `lockFocus` 造圖，結果在 Retina 上 backing store 是 2 倍，「300 點」的圖其實是 600 像素。縮放本來就該看像素，所以錯的是測試的前提，改成直接用 `NSBitmapImageRep` 造出確定的像素尺寸。

**端到端沒有驗過，也驗不了：** 這台機器旁邊沒有 iPhone，而那個選單項只有在有裝置的時候才會出現。可以確定的是圖片處理那一半（有測試）和接線本身（編譯通過、responder 那一半併進了 Skim 原本就在用的方法）。**選單有沒有出現、拍完照片有沒有進來，要你自己用手機試。** 如果選單裡沒看到那一項，先在 PDF 上點一下再按右鍵 —— AppKit 是從 first responder 開始找接收者的。

版本 `1.8.0 (20)`；測試 358 個檢查。

### 1.8.1 — 照片貼進 PDF

1.8.0 把 Continuity Camera 接成「拍照給 AI 問問題」，那是誤解。真正要的是**照片留在 PDF 裡**，所以改掉：拍下來的照片現在成為頁面上的一個標註，可以拖、可以縮放、可以刪除、可以 undo。

**載體是 anchored note，因為 Skim 的 note 格式本來就帶圖片。** `SKNPDFAnnotationImageKey = @"image"`、`initSkimNoteWithProperties:` 會把它讀回 `_image`、`SkimNoteProperties` 會把它寫出去、`SKNUtilities` 負責編成 PNG 再解回來、note 視窗甚至有把圖片拖出去存檔的程式碼。整套都在。

**但它從來不能用。** `SKNPDFAnnotationNote.m` 裡是 `@dynamic image;`，而**整個框架沒有任何地方實作那個 accessor** —— 所以 `[self image]`（`SkimNoteProperties` 自己在呼叫）和 `[note image]`（note 視窗的拖曳支援在呼叫）都是等著發生的 crash。改成 `@synthesize image = _image;`，既有的序列化就活過來了。這是這次改動裡唯一動到 SkimNotes 框架的地方，一行。

剩下的是讓它畫出來：`drawWithBox:inContext:` 先問 `drawPhotoWithBox:`，有圖片就畫圖片、沒有就走原本的 icon 路徑。原本那個 icon 方法被包在 `MAC_OS_X_VERSION_MIN_REQUIRED < 10.15` 的條件裡（在我們的 target 下根本沒編進去），所以拆成 `drawNoteIconWithBox:` 並補上 10.15 之後的分支，兩種 target 都只會有一份定義。

**畫得對不對是用渲染驗的，不是用眼睛。** 連結建置出來的 `SkimNotes.framework`，造一份單頁 PDF、放一個帶圖片的 note、把頁面畫成點陣圖再取樣像素。圖片刻意在**上緣**畫一條紅帶，這樣上下顛倒會立刻看得出來：

```
class from the factory   : SKNPDFAnnotationNote
centre / top / bottom    : BLUE / RED / BLUE   ← 位置對、沒有上下顛倒
outside the note         : white               ← 沒有溢出 bounds
properties carry an image: true
restored note has image  : true 200 x 200      ← 通過 notes 的存讀往返
```

同一個 harness 先抓到兩件事：直接 `[[SKNPDFAnnotationNote alloc] initSkimNoteWithBounds:]` 不保證拿到子類（改用 Skim 自己的 `newSkimNoteWithBounds:forType:` 工廠），以及上面那個 `@dynamic` 的空殼。

**其他細節：** 照片進 PDF 前先縮到最長邊 2048 並以 JPEG 0.82 重新編碼 —— 一份 PDF 收幾張一千兩百萬像素的原圖就寄不出去了。落點置中、最長邊不超過頁面的一半，而且不四捨五入（PDF 使用者空間是連續的，沒有像素格可以對齊；先前的四捨五入讓奇數尺寸的照片偏了半點）。anchored note 原本固定大小不可縮放，現在**帶圖片的才可縮放** —— icon 是 icon，照片要看得清楚。

想拿照片去問 AI 仍然可以：照片畫在頁面上，Command-Option 拖曳那塊區域就是既有的功能。

9 個新檢查（358 → 367）：縮放只看最長邊、不放大、空圖不產生標註、落點置中且維持比例、高的照片改由高度決定、頁面尺寸為零時不產生 bounds。

**還是要你用手機試。** 這台機器旁邊沒有 iPhone，選單項只有在有裝置時才會出現。畫圖與持久化這兩段現在是驗證過的，沒驗過的是「選單有沒有出現、照片有沒有真的從手機進來」。

**一個限制要知道：** 照片存在 Skim notes 裡，而 Anchora 把 notes 寫在檔案的 extended attributes（`SKMainDocument.m:457`）。同一台 Mac 上複製檔案通常留得住，但 email、上傳、壓縮多半會掉。要讓照片真的跟著 PDF 走給別人看，需要的是「結合到頁面」那一步 —— 你選的下一階段。

版本 `1.8.1 (21)`；測試 367 個檢查。

### 1.8.2 — 照片也可以從這台 Mac 進來

1.8.1 只做了從 iPhone 拍。同一個落地機制（`addPhotoNoteWithImage:`）現在有三個入口：

- **右鍵 →「Insert Picture…」** 開檔案選擇器，只列圖片。
- **⌘V 貼上**。剪貼簿上是圖片（或一個指向圖片檔的 URL）就貼成照片；**複製的 Skim 筆記仍然照舊貼成筆記** —— 先問 pasteboard 有沒有 `PDFAnnotation`，有就走原本的路。
- **從 Finder 拖進來**，而且**落在你放開的位置**，不是頁面正中央。

拖曳落點因此需要「以某一點為中心」的落點計算：算出尺寸之後以該點置中，再推回頁面範圍內 —— 一張有一半掛在頁面外的照片等於丟了一半。原本「置中於頁面」的版本現在就是同一個函式瞄準頁面中心。

`registerForDraggedTypes:` 多收 file URL、TIFF、PNG；`draggingEntered:` 對可讀成圖片的拖曳回 `NSDragOperationCopy`，其餘一律維持原本的顏色／線條樣式行為與 super 的處理。

8 個新檢查（367 → 375）：落在放開的點上、落在角落會被推回頁內、推回時不縮小、落點遠超出頁面也會回來，以及「置中於頁面」等同於「瞄準頁面中心」。

啟動與標註路徑做過回歸檢查（開檔、用 scripting 加一個 note，`notes=1 modified=true`）。**選檔／貼上／拖曳三個入口本身仍然要你動手試** —— 那些是互動路徑，這裡沒辦法自動驗。

版本 `1.8.2 (22)`；測試 375 個檢查。

### 發行腳本：重簽時 entitlements 被靜悄悄清空

還沒實際跑過公證（沒有 Developer ID 憑證），但先把這個問題找出來，免得帳號生效那天才卡住。

`package-release.sh` 對每個巢狀項目（Sparkle.framework、裡面的 Updater.app、SkimNotes.framework、Spotlight importer）跟主 app 都用 `codesign --force --sign` 重簽。`--force` 是整個換掉簽章，**沒有帶 `--entitlements` 的話新簽章的 entitlements 是空的** —— 不是保留舊的，是直接沒有。

對主 app 影響最大：`Skim.entitlements` 裡的 `com.apple.security.cs.disable-library-validation` 就是讓 hardened runtime 容忍 bundle 裡那些非 Apple 簽的 dylib（Sparkle 那一套）用的。沒有這個 entitlement，公證本身可能會過，**但 app 在啟用 hardened runtime 預設值的機器上會拒絕啟動或拒絕載入那些函式庫** —— 而且這種失敗不會出現在公證的錯誤訊息裡，只會在使用者那邊炸開。

修法：主 app 重簽時明確帶 `--entitlements Skim.entitlements`；巢狀項目改用 `--preserve-metadata=entitlements,requirements`，把它們自己建置時拿到的 entitlements原樣留著，而不是被 `--force` 一併清空。

**用 ad-hoc 簽章驗證過兩件事：**

```
主 app 重簽後：com.apple.security.automation.apple-events = true
             com.apple.security.cs.disable-library-validation = true
```

兩個 key 都在，符合 `Skim.entitlements`。同時也確認了明確帶 `--entitlements` 的副作用是對的：Xcode 對 ad-hoc 簽章的建置本來會附上除錯用的 `com.apple.security.get-task-allow = true`，重簽後這個 key 正確地消失了 —— 散布版本不該帶著這個。

```
Sparkle 的 Updater.app：重簽前後都是空的 entitlements dict
```

這個巢狀項目本來就沒有任何 entitlements，所以 `--preserve-metadata` 這次沒有實際保留到東西，但保留機制本身是對的：以後 Sparkle 版本更新、或換成走 `--options runtime` 的公證簽章路徑，若巢狀項目開始帶自己的 entitlements，這裡不會再把它們清空。

因為這只是簽章腳本的修正、不影響 app 行為，沒有 bump 版本；但既然重新跑過一次腳本，`Distribution/Anchora-1.8.2-macos-arm64.zip` 的 SHA-256 從 `c978ea7c…` 變成 `fdc7594c…`（bundle byte-for-byte 只差在 entitlements blob，功能沒有變化）。

**還沒驗到的：** 真正的 `--options runtime` + Developer ID 簽章路徑，以及公證本身。這些要等 Apple Developer Program 帳號那邊的憑證與 app-specific password 就緒才能跑。

### 發行腳本：實際跑過一次公證，抓到真正的缺口

Apple Developer Program 帳號生效、Developer ID Application 憑證建好、notarytool 認證也存好之後，第一次真的送出去公證，結果是 `status: Invalid`。拉出 `xcrun notarytool log` 才看到具體問題，跟前一輪「entitlements 被清空」是完全不同的另一個洞。

**上一輪的修法漏了五個執行檔。** 舊的巢狀簽章迴圈只抓 `.framework`／`.app`／`.xpc`／`.mdimporter` 四種目錄型 bundle，但公證檢查的是**每一個 Mach-O 執行檔**，不是只看 bundle。實際列出 bundle 裡全部 11 個執行檔，對照公證回報的錯誤，缺口精準對上：

- `Contents/SharedSupport/skimpdf`、`skimnotes` —— 兩個裸執行檔，**根本沒包在任何 bundle 裡**，舊迴圈連碰都碰不到。
- `Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate` —— 雖然人在 `.framework` 目錄底下，但它是 framework 自己主執行檔以外**另一個獨立的輔助工具**，簽 `Sparkle.framework` 這個 bundle 不會連帶簽到它。
- `SkimTransitions.plugin`、`Skim.qlgenerator` —— 這兩種 bundle 類型（`.plugin`、`.qlgenerator`）舊清單根本沒列進去。

公證回報的錯誤也精準對應：這五個都是「未用有效 Developer ID 簽章」與「簽章缺 secure timestamp」（因為它們從頭到尾帶的都是 Xcode 建置時給的 ad-hoc 簽章，沒人碰過），其中 `skimpdf`／`skimnotes` 還多了「帶有 get-task-allow entitlement」——這是 Xcode 對 ad-hoc 建置附加的除錯用權限，正式散布版本不該有。

**修法比想像中更簡單，而不是更保守。** 一開始想用 `--preserve-metadata=entitlements` 把每個東西原本的 entitlements 保留下來，但這次的錯誟訊息剛好證明那是錯的方向——`skimpdf`／`skimnotes` 原本的 entitlements 裡就帶著問題本身（get-task-allow），保留等於把公證會拒絕的理由原封不動搬過去。查證後發現更正確的做法反而更直接：**除了主 app 需要 `Skim.entitlements`（給 hardened runtime 用的 `disable-library-validation`）之外，其餘一律不帶任何 entitlements**——這個 app 沒有 sandboxed，Sparkle 內部的東西本來就不需要任何特殊權限，`Updater.app` 重簽前後 entitlements 都是空的字典就是證據。

加了一個新的簽章步驟，跑在巢狀 bundle 迴圈之前：找出 bundle 裡**所有**設了可執行位元、且 `file` 認得是 Mach-O 的檔案，逐一簽署，不分它在不在被辨識的 bundle 類型裡。之後巢狀 bundle 迴圈再補上 `.plugin`／`.qlgenerator` 兩種類型，跑完換外層 app。一個 bundle 的主執行檔會先被這個新步驟簽過一次、隨後又被 bundle 層級的簽章再簽一次——多做一次但無害，換來的是不用去猜「這個副檔名算不算 bundle」。

**用 ad-hoc 簽章實測驗證（這台機器上仍然沒有真的送公證，因為那要花 Apple 的公證額度且需要網路等候）：**

```
簽章前：skimpdf / skimnotes 的 get-task-allow entitlement 都是 1（存在）
簽章前：五個目標的 Signature 全是 adhoc

簽章後：五個目標的 get-task-allow entitlement 全部變成 0
簽章後：「Sign ad-hoc」那段輸出列出全部 12 個路徑（11 個執行檔 + 外層 app）都被 replacing existing signature
codesign --verify --deep --strict：PASSED
主 app 的 Skim.entitlements 兩個 key 沒有被這次改動動到
```

375 個既有檢查照跑，孤兒方法檢查照過——這次改動只碰簽章腳本，沒有動到 app 本身的程式碼。

**還沒驗到的：** 真正送到 Apple 公證伺服器、拿到 `status: Accepted`、以及 `stapler staple` 真的把票證蓋上去。上面的驗證只能證明「這次找到的五個缺口確實被補上」，公證服務本身還可能發現別的問題（例如某個框架版本本身的簽章要求變動）。下一次實際送出去的結果，麻煩把完整輸出（尤其是 `status` 那一行，失敗的話還有 submission id）貼回來，才能繼續往下查。

---

### 1.9.0 — 複習佇列，以及能打勾的自我測驗清單

Recall 和 Quiz 用過幾週之後回頭看，發現一個浪費：每一次批改都是真正的訊號——哪裡答錯了、哪裡漏了——但那個訊號用完即丟，transcript 一捲過去就沒了。這一版把它接住。

**每一次 Recall 或 Quiz 批改完成，自動進複習佇列。** 不分答對答錯全部收——要分辨這次是不是答對了，得去解析模型自己寫的那段散文，而漏掉一個真正答錯的項目，代價遠高於多收一個其實答對了的項目（複習一次已經會的東西，成本只是幾秒鐘）。

排程是固定的五階：**1 天 → 3 天 → 7 天 → 14 天 → 30 天**，不是真的間隔重複演算法，就是「晚點再看一次，答對了就看得更少次，答錯了就重來」。側欄多了第四個分頁 `Review`，跟 `Inbox` 一樣是**跨文件的全域清單**——複習項目存的是**完整的批改內容原文**，跟當初在對話裡看到的一模一樣，複習就是重讀一次，沒有東西要重新生成。卡片上兩個按鈕：`Knew it` 把排程往後推一階，`Still shaky` 重置回第一階；另外有一個連結跳回原文件原頁碼，連結到別份文件會先開檔再跳頁。

**Study map 的自我測驗，從純文字變成能打勾的清單。** 那一節內容其實一直都在（study map prompt 最後一段就是「讀完應該能默答的問題」），只是純文字看完就過去了。這次：

- Prompt 把那一節的標題**固定成英文**「## Self-test questions」，跟 Paper map 八個固定英文標題同一招——不管回覆語言是中文還是英文，app 都能穩定找到是哪一節，而不是去猜「最後一節大概是它」。
- 解析成逐條可勾選的項目，而不是整節一次勾完——重點是讓讀者注意到「這幾條我真的答不出來」，不是「我看過這份清單」。
- **勾選狀態用題目文字本身的雜湊當 id，不是隨機產生。** 這代表同一份文件重建 study map 之後，沒有變動過的題目會保留原本的打勾狀態，只有真正新增或刪除的題目才會變動——不會因為重建一次整份清單就被打回原形。

**架構上沿用既有慣例，沒有另外發明機制。** 兩個功能都落在 `AnchoraStore` 既有的 per-document JSON 檔案裡（跟已經在用的 `maps` 欄位並列），複習佇列額外提供一個跨文件掃描的入口；`AnchoraPaneModel`/`AnchoraPaneView` 從三個分頁擴成四個，新分頁的接法完全比照 `Inbox` 當初的樣板。Recall／Quiz 批改完成時要不要送進複習佇列，用的是跟 `aiPendingMapKind` 一樣的「請求開始前設一個 pending 屬性、建立 turn 時消耗掉」的手法，而不是幫每一個呼叫點的長參數列多加一個參數。

**過程中因為橋接命名的不確定性，把所有新增的 Swift API 都寫了明確的 `@objc(...)` selector。** 從既有程式碼裡（`saveMap(response:...)` 橋接成 `saveMapWithResponse:...`）能歸納出 Swift 對 Objective-C 選擇器有一套「幫第一個具名參數插入 With」的規則，但介系詞或 `id` 這種縮寫開頭的參數會不會照這規則走、大小寫怎麼處理，光看兩個例子沒辦法完全確定。與其賭規則，索性把新加的每一個會被 `.m` 呼叫到的方法都明確寫出選擇器名稱，這是這個檔案裡原本就存在的做法（`AnchoraPrompts` 裡幾個方法也是這樣處理的），這次只是把它套用得更徹底。

44 個新檢查（375 → 419）：自我測驗一節用固定標題而非位置找到、大小寫不影響比對、找不到時回傳 `NSNotFound` 而不是誤判成別的段落、逐條題目正確拆分、沒有清單標記的純文字段落退回成單一項目、勾選狀態依文字雜湊在重建後存活、新題目預設未勾選、被刪掉的題目也從清單裡消失；複習項目剛建立時「還沒到期」（Recall/Quiz 本身已經在 transcript 裡給過一次回饋，佇列的用途是晚點再看，不是立刻又看一次）、答對推進排程且不會超出五階讀出陣列外、答錯重置、佇列橫跨多份文件且各自保留自己的 `documentPath`、依到期時間由舊到新排序；以及 `AnchoraMapModel` 這一側：換一張 map 會清掉舊的自我測驗狀態直到 store 重新回答、`NSNotFound` 不會被誤存成真正的索引、勾選會同時反映在本地狀態與往外回報給 store 的呼叫上。

**過程中做了一次真實的回歸測試。** 因為這次大幅改動 `SKRightSideViewController.m`（新增第四個 property、新的 pending 屬性、`buildAIInterface` 的接線），光靠建置成功不足以確信側欄真的能正常初始化，所以另外開了一份雙頁測試 PDF、實際啟動 app、用 AppleScript 新增一個標註、確認 `modified` 正確翻轉、且過程中 app 全程存活——`buildAIInterface` 是在 `viewDidLoad` 裡跑的，這代表新的四分頁側欄接線在文件開啟的當下就真的執行過一次，而不只是編譯器沒有報錯。

**還沒驗到的地方，說清楚：** 兩個功能的觸發點都是真正的 AI 回覆（Recall/Quiz 批改完成、Study map 建好），這裡沒有 API 額度能跑一次真實網路請求，所以「佇列會不會在一次真的 Recall/Quiz 之後正確跳出項目」與「自我測驗清單能不能正確解析真實模型輸出的固定標題」都只驗證到手寫樣本這一層，沒有驗證到真實 API 回應這一層。

版本 `1.9.0 (23)`；測試 419 個檢查。

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
- `Study`／`Scientific` 閱讀 profile。快捷列各三顆：Study 是 Explain／Recall／Quiz，Scientific 是 Methods／Figure／Evidence；其餘動作（Study map、Translate、Clinical、Question、Hypothesis）在 ••• 裡。
- 當頁回饋：`Recall` 對照你憑記憶寫下的一句話，`Quiz` 出 2–3 題並在你作答後逐題批改。
- 側欄主體可切換 `Chat`／`Map`／`Inbox`／`Review` 四面，各自使用整個高度。
- `Review` 是跨文件的複習佇列：Recall／Quiz 批改完成自動收錄，`Knew it`／`Still shaky` 推進或重置排程（1／3／7／14／30 天）。
- Study map 的自我測驗一節可逐條打勾，勾選狀態依題目文字保存，重建 map 不會清空既有進度。
- 輸入框 Return 送出、Shift-Return 換行，並隨內容長高（約六行後改為捲動）。
- CONTEXT 為一行狀態；抽取出來的文字可點開 popover 檢查全文。
- 空白啟動（或 Dock 點擊而沒有視窗）時自動叫出開檔面板，不再是一片空白。
- 照片可從 iPhone 拍照／掃描、從檔案選取、⌘V 貼上或從 Finder 拖入，成為頁面上可拖曳縮放的標註，隨 Skim notes 保存。
- 退出時若有未儲存的修改會詢問，不再靜悄悄地丟掉標註。
- 雜念收納：⌘⇧J 從任何地方寫一行，記下當時的文件與頁碼；側欄 Inbox 抽屜管理。
- Study map 與 Paper map 存在本機，重開文件時自動還原。
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
| 儲存 | Application Support 下的 JSON，原子寫入 | annotation 屬於 PDF；讀書計畫與雜念不屬於，但必須留得住。 |
| 文件識別 | 檔案路徑雜湊，另存 bookmark | Anchora 會改寫它讀的 PDF，內容雜湊會讓剛建好的 map 變孤兒。 |
| 全域捕捉 | app 內的 local event monitor | 系統層級熱鍵需要 Input Monitoring 授權，這個 app 沒有別的理由去要。 |
| 輸入框 | 自訂 NSTextView 而非 SwiftUI 多行 TextField | 後者不分 Shift 一律以 Return 送出，沒有辦法換行。 |
| 動態高度 | 由 view 量測後回報，host 設約束 | 寬度單向由側欄給，高度往外送，不會形成 intrinsic size 的量測迴圈。 |
| 空白啟動 | 沒有可還原的工作階段時叫出開檔面板 | 上游的「什麼都不顯示」對第一次使用的人是純粹的困惑。 |
| 退出檢查 | 明確實作 `applicationShouldTerminate:` | 自動的未儲存檢查在這個 app 裡沒有發生，⌘Q 會直接丟掉標註。 |
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
- Release 附件：`Distribution/Anchora-1.9.0-macos-arm64.zip`（8.9 MB，SHA-256 `848dbe05…`）
- 版本：`1.9.0 (23)`
- 最低系統：macOS 14.0
- 大小：約 17 MB
- Bundle ID：`com.kris.anchora`

## 後續候選項目（尚未實作）

- Paper Map 段落內容的 Markdown 渲染（需與既有的 evidence／quote 範圍標示整合）。
- Markdown 表格支援。
- 取得 Developer ID 憑證並實際跑通公證流程（腳本已就緒，尚未驗證）。
