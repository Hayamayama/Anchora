//
//  AnchoraResponsesClient.swift
//  Anchora
//
//  A single streaming turn against the OpenAI Responses API.  Replaces the
//  hand-rolled NSURLSessionDataDelegate + SSE buffer that used to live in the
//  sidebar view controller: request construction, streaming, delta coalescing,
//  web-source collection and error mapping all happen here, and the caller
//  only sees status / delta / finish callbacks on the main thread.
//

import Foundation

/// Everything a turn needs.  Built by the caller, then handed to a client and
/// not mutated again.
@objc(AnchoraRequest)
public final class AnchoraRequest: NSObject {
    @objc public var model: String = AnchoraSettings.defaultModelIdentifier
    @objc public var instructions: String = ""
    @objc public var prompt: String = ""
    @objc public var imageDataURL: String?
    @objc public var fileDataURL: String?
    @objc public var fileName: String?
    /// Prior turns as `["role": "user"|"assistant", "text": …]`, oldest first.
    @objc public var priorMessages: [[String: String]] = []
    @objc public var maxOutputTokens: Int = 8000
    @objc public var webSearchEnabled: Bool = false
    @objc public var timeout: TimeInterval = 120.0

    @objc public override init() {
        super.init()
    }
}

@objc(AnchoraResponsesClient)
public final class AnchoraResponsesClient: NSObject {

    private static let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    /// Paper maps arrive as many small deltas; rendering every one of them is
    /// O(n^2) CoreText work in the sidebar, so batch them.
    private static let deltaFlushInterval: TimeInterval = 0.12

    private let apiKey: String
    private let request: AnchoraRequest

    /// `task`, `pendingDelta`, `flushScheduled` and `finished` are touched from
    /// three places at once: the streaming task, the delta-flush task, and
    /// -cancel on the main thread.  `receivedText` and `webSources` are the
    /// exception — they are only ever mutated inside `run()`, and only read
    /// from there.
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var pendingDelta = ""
    private var flushScheduled = false
    private var finished = false
    private var receivedText = ""
    private var webSources: [String] = []

    /// A short human-readable phase, e.g. "Uploading PDF to Anchora…".
    @objc public var onStatus: ((String) -> Void)?
    /// A batch of newly streamed output text.
    @objc public var onDelta: ((String) -> Void)?
    /// `text` is the complete answer, `errorMessage` is set when the turn
    /// failed, `cancelled` when the user pressed Stop.
    @objc public var onFinish: ((String?, [String], String?, Bool) -> Void)?

    @objc public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return task != nil
    }

    @objc public init(apiKey: String, request: AnchoraRequest) {
        self.apiKey = apiKey
        self.request = request
        super.init()
    }

    // MARK: - Lifecycle

    @objc public func start() {
        lock.lock()
        guard task == nil else { lock.unlock(); return }
        let newTask = Task { [weak self] in
            guard let self else { return }
            await self.run()
        }
        task = newTask
        lock.unlock()
    }

    @objc public func cancel() {
        lock.lock()
        let running = task
        task = nil
        lock.unlock()
        guard let running else { return }
        running.cancel()
        // Deliberately reports no text and no sources: those belong to the
        // streaming task, and the cancelled path does not use them.
        finish(text: nil, webSources: [], errorMessage: nil, cancelled: true)
    }

    // MARK: - Request body

    private func inputItems() -> [[String: Any]] {
        var items: [[String: Any]] = request.priorMessages.compactMap { message in
            guard let role = message["role"], let text = message["text"] else { return nil }
            let type = (role == "assistant") ? "output_text" : "input_text"
            return ["role": role, "content": [["type": type, "text": text]]]
        }

        var content: [[String: Any]] = [["type": "input_text", "text": request.prompt]]
        if let imageDataURL = request.imageDataURL, imageDataURL.isEmpty == false {
            content.append(["type": "input_image", "image_url": imageDataURL, "detail": "high"])
        }
        if let fileDataURL = request.fileDataURL, fileDataURL.isEmpty == false {
            content.append(["type": "input_file",
                            "filename": request.fileName ?? "document.pdf",
                            "file_data": fileDataURL,
                            "detail": "high"])
        }
        items.append(["role": "user", "content": content])
        return items
    }

    private func makeURLRequest() throws -> URLRequest {
        var body: [String: Any] = [
            "model": request.model,
            "stream": true,
            "store": false,
            "max_output_tokens": request.maxOutputTokens,
            "instructions": request.instructions,
            "input": inputItems(),
        ]
        if request.webSearchEnabled {
            body["tools"] = [["type": "web_search", "search_context_size": "medium"]]
            body["include"] = ["web_search_call.action.sources"]
        }

        var urlRequest = URLRequest(url: AnchoraResponsesClient.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = request.timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    // MARK: - Streaming

    private func run() async {
        let urlRequest: URLRequest
        do {
            urlRequest = try makeURLRequest()
        } catch {
            finish(text: nil, webSources: [], errorMessage: "Could not prepare the AI request: \(error.localizedDescription)", cancelled: false)
            return
        }

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            if statusCode >= 400 {
                let message = await failureMessage(statusCode: statusCode, bytes: bytes)
                finish(text: nil, webSources: webSources, errorMessage: message, cancelled: false)
                return
            }

            emitStatus("Anchora is reading the document…")

            for try await line in bytes.lines {
                if Task.isCancelled { break }
                guard line.hasPrefix("data: ") else { continue }
                let payload = String(line.dropFirst("data: ".count))
                if payload.isEmpty || payload == "[DONE]" { continue }
                guard let data = payload.data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }
                handle(event: event)
            }

            if Task.isCancelled {
                return
            }
            if receivedText.isEmpty {
                finish(text: nil, webSources: webSources, errorMessage: "No text was returned by OpenAI.", cancelled: false)
            } else {
                finish(text: receivedText, webSources: webSources, errorMessage: nil, cancelled: false)
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            finish(text: receivedText.isEmpty ? nil : receivedText,
                   webSources: webSources,
                   errorMessage: "Network error: \(error.localizedDescription)",
                   cancelled: false)
        }
    }

    private func handle(event: [String: Any]) {
        collectWebSources(in: event)

        switch event["type"] as? String {
        case "response.output_text.delta":
            if let delta = event["delta"] as? String, delta.isEmpty == false {
                receivedText += delta
                enqueue(delta: delta)
            }
        case "response.completed":
            // Most responses stream text deltas, but a valid completion can
            // carry its text only in the terminal event.  Accepting it here
            // stops a successful request from looking blank.
            if receivedText.isEmpty,
               let response = event["response"] as? [String: Any],
               let text = AnchoraResponsesClient.outputText(from: response) {
                receivedText += text
                enqueue(delta: text)
            }
        case "response.failed":
            let response = event["response"] as? [String: Any]
            let failure = response?["error"] as? [String: Any]
            let message = failure?["message"] as? String ?? "The request failed."
            emitStatus("OpenAI error: \(message)")
        case "error":
            let message = event["message"] as? String ?? "Unknown error"
            emitStatus("OpenAI error: \(message)")
        default:
            break
        }
    }

    private static func outputText(from response: [String: Any]) -> String? {
        guard let output = response["output"] as? [[String: Any]] else { return nil }
        var parts: [String] = []
        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for entry in content where entry["type"] as? String == "output_text" {
                if let text = entry["text"] as? String, text.isEmpty == false {
                    parts.append(text)
                }
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// The Responses payload nests web-search sources differently depending on
    /// the tool call, so walk the whole event rather than guessing a path.
    private func collectWebSources(in object: Any) {
        if let dictionary = object as? [String: Any] {
            if let sources = dictionary["sources"] as? [Any] {
                for source in sources {
                    let urlString = (source as? [String: Any])?["url"] as? String ?? (source as? String)
                    if let urlString, urlString.isEmpty == false, webSources.contains(urlString) == false {
                        webSources.append(urlString)
                    }
                }
            }
            for value in dictionary.values {
                collectWebSources(in: value)
            }
        } else if let array = object as? [Any] {
            for value in array {
                collectWebSources(in: value)
            }
        }
    }

    private func failureMessage(statusCode: Int, bytes: URLSession.AsyncBytes) async -> String {
        var body = ""
        if let collected = try? await bytes.reduce(into: Data(), { $0.append($1) }) {
            body = String(data: collected, encoding: .utf8) ?? ""
        }
        if let data = body.data(using: .utf8),
           let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = payload["error"] as? [String: Any],
           let message = error["message"] as? String {
            return "OpenAI request failed (HTTP \(statusCode)): \(message)"
        }
        return "OpenAI request failed (HTTP \(statusCode)). Check your API key, billing, and model access."
    }

    // MARK: - Callbacks

    private func emitStatus(_ status: String) {
        DispatchQueue.main.async { [onStatus] in
            onStatus?(status)
        }
    }

    private func enqueue(delta: String) {
        lock.lock()
        pendingDelta += delta
        let alreadyScheduled = flushScheduled
        flushScheduled = true
        lock.unlock()
        guard alreadyScheduled == false else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(AnchoraResponsesClient.deltaFlushInterval * 1_000_000_000))
            self?.flushPendingDelta()
        }
    }

    private func flushPendingDelta() {
        lock.lock()
        flushScheduled = false
        let batch = pendingDelta
        pendingDelta = ""
        lock.unlock()
        guard batch.isEmpty == false else { return }
        DispatchQueue.main.async { [onDelta] in
            onDelta?(batch)
        }
    }

    private func finish(text: String?, webSources: [String], errorMessage: String?, cancelled: Bool) {
        lock.lock()
        guard finished == false else { lock.unlock(); return }
        finished = true
        task = nil
        lock.unlock()

        flushPendingDelta()
        DispatchQueue.main.async { [onFinish] in
            onFinish?(text, webSources, errorMessage, cancelled)
        }
    }
}
