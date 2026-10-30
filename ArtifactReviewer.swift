import Cocoa
import SwiftUI
import WebKit

// MARK: - Models
struct LineComment: Codable, Identifiable, Equatable {
    var id: String
    var file: String
    var filename: String
    var line: Int
    var lineContent: String
    var comment: String
    var timestamp: Double
    var formattedDate: String

    static func == (lhs: LineComment, rhs: LineComment) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - State Manager
class ReviewerState: ObservableObject {
    @Published var filePath: String = ""
    @Published var fileName: String = ""
    @Published var markdownContent: String = ""
    @Published var lineComments: [LineComment] = []
    @Published var viewMode: String = "line" // "line" or "rendered"
    @Published var statusMessage: String = ""
    @Published var statusColor: Color = .gray
    @Published var requestFeedback: Bool = true
    @Published var summary: String = ""
    
    var fileURL: URL? {
        guard !filePath.isEmpty else { return nil }
        return URL(fileURLWithPath: filePath)
    }

    func loadFile(_ path: String) {
        self.filePath = path
        let url = URL(fileURLWithPath: path)
        self.fileName = url.lastPathComponent
        
        // Read file content
        if let data = try? Data(contentsOf: url),
           let content = String(data: data, encoding: .utf8) {
            self.markdownContent = content
        } else {
            self.markdownContent = "*(Unable to load file at \(path))*"
        }

        // Read metadata if present
        let metaPath = path + ".metadata.json"
        if FileManager.default.fileExists(atPath: metaPath),
           let metaData = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
           let meta = try? JSONDecoder().decode(ArtifactMetadata.self, from: metaData) {
            self.requestFeedback = meta.requestFeedback ?? false
            self.summary = meta.summary ?? ""
        }

        loadSavedLineComments()
    }

    func loadSavedLineComments() {
        guard let url = fileURL else { return }
        let dir = url.deletingLastPathComponent().path
        let commentsFile = URL(fileURLWithPath: dir).appendingPathComponent("line_comments.json")
        if FileManager.default.fileExists(atPath: commentsFile.path),
           let data = try? Data(contentsOf: commentsFile),
           let items = try? JSONDecoder().decode([LineComment].self, from: data) {
            self.lineComments = items.filter { $0.file == self.filePath }
        }
    }

    func saveLineComments() {
        guard let url = fileURL else { return }
        let dir = url.deletingLastPathComponent().path
        let commentsFile = URL(fileURLWithPath: dir).appendingPathComponent("line_comments.json")

        // 1. Save line_comments.json in artifact dir
        if let enc = try? JSONEncoder().encode(lineComments) {
            try? enc.write(to: commentsFile)
        }

        // 2. Also save to state/line_comments.json
        let exeDir = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
        let stateCommentsPath = exeDir.appendingPathComponent("state/line_comments.json")
        try? FileManager.default.createDirectory(at: exeDir.appendingPathComponent("state"), withIntermediateDirectories: true)
        if let enc = try? JSONEncoder().encode(lineComments) {
            try? enc.write(to: stateCommentsPath)
        }

        // 3. Update feedback.md with line comments
        updateFeedbackMarkdown()
    }

    func updateFeedbackMarkdown() {
        guard let url = fileURL, !lineComments.isEmpty else { return }
        let dir = url.deletingLastPathComponent().path
        let feedbackMdPath = URL(fileURLWithPath: dir).appendingPathComponent("feedback.md")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateStr = formatter.string(from: Date())

        var md = "# Artifact Line Review Feedback\n\n"
        md += "### Review on `\(fileName)` (\(dateStr))\n"
        for c in lineComments.sorted(by: { $0.line < $1.line }) {
            let quote = c.lineContent.isEmpty ? "" : " (`\(c.lineContent)`)"
            md += "- **Line \(c.line)**\(quote):\n  > \(c.comment.replacingOccurrences(of: "\n", with: "\n  > "))\n"
        }
        try? md.write(to: feedbackMdPath, atomically: true, encoding: .utf8)
    }

    func syncClipboardWithLineComments() {
        guard !lineComments.isEmpty else { return }
        var text = "Review comments on \(fileName):\n"
        for c in lineComments.sorted(by: { $0.line < $1.line }) {
            let quote = c.lineContent.isEmpty ? "" : " (\(c.lineContent))"
            text += "- Line \(c.line)\(quote): \(c.comment)\n"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func addLineComment(id: String, line: Int, lineContent: String, comment: String, timestamp: Double) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let dateStr = formatter.string(from: Date(timeIntervalSince1970: timestamp))

        let item = LineComment(
            id: id,
            file: filePath,
            filename: fileName,
            line: line,
            lineContent: lineContent,
            comment: comment,
            timestamp: timestamp,
            formattedDate: dateStr
        )

        lineComments.removeAll { $0.id == id }
        lineComments.append(item)
        saveLineComments()
        syncClipboardWithLineComments()

        statusMessage = "✅ Comment added on Line \(line) & copied to clipboard!"
        statusColor = .cyan

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if self.statusMessage.contains("Line \(line)") {
                self.statusMessage = ""
            }
        }
    }

    func deleteLineComment(id: String) {
        lineComments.removeAll { $0.id == id }
        saveLineComments()
        syncClipboardWithLineComments()
        statusMessage = "🗑️ Line comment removed"
        statusColor = .gray
    }

    func approveAndProceed() {
        let exeDir = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
        ArtifactApproval.approveArtifact(path: filePath, baseDir: exeDir, showToast: true)

        self.requestFeedback = false
        statusMessage = "✅ Plan Approved! Session unblocked & 'proceed' copied."
        statusColor = .green
    }
}

// MARK: - Script Message Handler Bridge
class WebScriptHandler: NSObject, WKScriptMessageHandler {
    weak var state: ReviewerState?

    init(state: ReviewerState) {
        self.state = state
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let action = dict["action"] as? String else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let state = self.state else { return }
            if action == "addLineComment" {
                let id = dict["id"] as? String ?? "c-\(Int(Date().timeIntervalSince1970 * 1000))"
                let line = dict["line"] as? Int ?? 1
                let lineContent = dict["lineContent"] as? String ?? ""
                let comment = dict["comment"] as? String ?? ""
                let timestamp = dict["timestamp"] as? Double ?? Date().timeIntervalSince1970
                state.addLineComment(id: id, line: line, lineContent: lineContent, comment: comment, timestamp: timestamp)
            } else if action == "deleteLineComment" {
                if let id = dict["id"] as? String {
                    state.deleteLineComment(id: id)
                }
            }
        }
    }
}

// MARK: - WebKit Markdown View with Per-Line Comments
struct MarkdownWebView: NSViewRepresentable {
    @ObservedObject var state: ReviewerState
    let resourcesDir: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    class Coordinator: NSObject {
        var scriptHandler: WebScriptHandler
        init(state: ReviewerState) {
            self.scriptHandler = WebScriptHandler(state: state)
        }
    }

    func makeNSView(context: Context) -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator.scriptHandler, name: "reviewer")

        let config = WKWebViewConfiguration()
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let markedPath = resourcesDir.appendingPathComponent("marked.min.js").path
        var markedJS = ""
        if FileManager.default.fileExists(atPath: markedPath),
           let jsData = try? Data(contentsOf: URL(fileURLWithPath: markedPath)),
           let js = String(data: jsData, encoding: .utf8) {
            markedJS = js
        } else {
            markedJS = "// marked fallback\nfunction marked(m){ return '<pre>' + m + '</pre>'; }"
        }

        let escapedMarkdown = state.markdownContent
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        var commentsJSON = "[]"
        if let data = try? JSONEncoder().encode(state.lineComments),
           let str = String(data: data, encoding: .utf8) {
            commentsJSON = str
        }

        let viewMode = state.viewMode

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          * { box-sizing: border-box; }
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
            font-size: 13px;
            line-height: 1.6;
            color: #c9d1d9;
            background-color: #0d1117;
            padding: 16px 20px;
            margin: 0;
            word-wrap: break-word;
          }
          /* GFM Common Styles */
          h1, h2, h3, h4, h5, h6 { color: #f0f6fc; font-weight: 600; margin-top: 20px; margin-bottom: 12px; }
          h1 { font-size: 22px; border-bottom: 1px solid #21262d; padding-bottom: 6px; }
          h2 { font-size: 18px; border-bottom: 1px solid #21262d; padding-bottom: 5px; }
          h3 { font-size: 15px; }
          a { color: #58a6ff; text-decoration: none; }
          a:hover { text-decoration: underline; }
          code {
            font-family: ui-monospace, SFMono-Regular, SF Mono, Menlo, monospace;
            font-size: 11.5px;
            background-color: #161b22;
            padding: 2px 5px;
            border-radius: 4px;
            border: 1px solid #30363d;
            color: #79c0ff;
          }
          pre { background-color: #161b22; border: 1px solid #30363d; border-radius: 6px; padding: 12px; overflow: auto; }
          pre code { background-color: transparent; padding: 0; border: none; color: #e6edf3; font-size: 12px; }
          blockquote { padding: 0 14px; color: #8b949e; border-left: 4px solid #30363d; margin: 12px 0; }
          table { border-collapse: collapse; width: 100%; margin-bottom: 14px; }
          table th, table td { padding: 6px 10px; border: 1px solid #30363d; }
          table th { background-color: #161b22; color: #f0f6fc; }
          table tr:nth-child(2n) { background-color: #161b2255; }
          .alert { padding: 10px 14px; margin-bottom: 14px; border-radius: 6px; border-left: 4px solid; }
          .alert-note { background-color: #121d2f; border-color: #1f6feb; color: #58a6ff; }
          .alert-tip { background-color: #102319; border-color: #238636; color: #3fb950; }
          .alert-important { background-color: #1c192d; border-color: #8957e5; color: #a371f7; }
          .alert-warning { background-color: #2b2210; border-color: #d29922; color: #d29922; }
          .alert-caution { background-color: #2c1619; border-color: #f85149; color: #f85149; }
          .alert-title { font-weight: bold; margin-bottom: 3px; }

          /* Per-Line Review Styles */
          .line-review-table {
            width: 100%;
            border-collapse: collapse;
            font-family: ui-monospace, SFMono-Regular, SF Mono, Menlo, monospace;
            font-size: 12px;
          }
          .line-row {
            display: flex;
            align-items: flex-start;
            min-height: 22px;
            line-height: 22px;
            padding: 0;
            border-radius: 3px;
            position: relative;
          }
          .line-row:hover {
            background-color: rgba(56, 139, 253, 0.08);
          }
          .line-gutter {
            width: 58px;
            min-width: 58px;
            display: flex;
            align-items: center;
            justify-content: flex-end;
            padding-right: 8px;
            color: #6e7681;
            user-select: none;
            position: relative;
            border-right: 1px solid #30363d;
            margin-right: 12px;
          }
          .line-num {
            font-size: 11px;
            cursor: pointer;
          }
          .line-add-btn {
            display: none;
            position: absolute;
            right: -8px;
            top: 2px;
            width: 16px;
            height: 16px;
            background: #1f6feb;
            color: white;
            border: none;
            border-radius: 3px;
            font-size: 12px;
            line-height: 15px;
            text-align: center;
            cursor: pointer;
            z-index: 5;
            font-weight: bold;
          }
          .line-row:hover .line-add-btn {
            display: block;
          }
          .has-comment-badge {
            font-size: 10px;
            margin-right: 4px;
            color: #58a6ff;
          }
          .line-code {
            flex: 1;
            white-space: pre-wrap;
            word-break: break-all;
            color: #e6edf3;
          }
          .line-code.heading { color: #79c0ff; font-weight: bold; }
          .line-code.comment { color: #8b949e; }
          .line-code.list-item { color: #e6edf3; }

          /* Inline Comment Card & Form */
          .comment-box-container {
            margin: 4px 12px 10px 70px;
            background: #161b22;
            border: 1px solid #388bfd;
            border-radius: 6px;
            padding: 10px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.5);
          }
          .form-header {
            font-size: 11px;
            font-weight: bold;
            color: #58a6ff;
            margin-bottom: 6px;
          }
          .comment-textarea {
            width: 100%;
            height: 52px;
            background: #0d1117;
            border: 1px solid #30363d;
            border-radius: 4px;
            color: #c9d1d9;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            font-size: 12px;
            padding: 6px;
            resize: vertical;
          }
          .comment-textarea:focus {
            outline: none;
            border-color: #58a6ff;
          }
          .form-actions {
            display: flex;
            justify-content: flex-end;
            gap: 8px;
            margin-top: 6px;
          }
          .btn-cancel, .btn-submit {
            padding: 4px 10px;
            font-size: 11px;
            border-radius: 4px;
            cursor: pointer;
            font-weight: 600;
          }
          .btn-cancel {
            background: #21262d;
            color: #c9d1d9;
            border: 1px solid #30363d;
          }
          .btn-submit {
            background: #238636;
            color: white;
            border: 1px solid #2ea043;
          }
          .comment-card {
            margin: 4px 12px 8px 70px;
            background: #161b22;
            border: 1px solid #30363d;
            border-left: 3px solid #58a6ff;
            border-radius: 5px;
            padding: 8px 12px;
          }
          .card-header {
            display: flex;
            justify-content: space-between;
            font-size: 10.5px;
            color: #8b949e;
            margin-bottom: 4px;
          }
          .card-badge {
            color: #58a6ff;
            font-weight: bold;
          }
          .card-del-btn {
            background: none;
            border: none;
            color: #8b949e;
            cursor: pointer;
            font-size: 11px;
            padding: 0 4px;
          }
          .card-del-btn:hover { color: #f85149; }
          .card-text {
            color: #f0f6fc;
            font-size: 12px;
            line-height: 1.4;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          }
        </style>
        <script>
        \(markedJS)
        </script>
        </head>
        <body>
        <div id="content"></div>

        <script>
        const rawMarkdown = `\(escapedMarkdown)`;
        const savedComments = \(commentsJSON);
        const currentMode = "\(viewMode)";

        function renderView() {
          const container = document.getElementById("content");
          if (currentMode === "rendered") {
            // Full Rendered GFM Document View
            let html = "";
            try {
              if (typeof marked !== 'undefined') {
                html = (typeof marked.parse === 'function') ? marked.parse(rawMarkdown) : marked(rawMarkdown);
              } else {
                html = "<pre>" + escapeHtml(rawMarkdown) + "</pre>";
              }
            } catch(e) {
              html = "<pre>" + escapeHtml(rawMarkdown) + "</pre>";
            }

            // Transform GitHub alerts
            html = html.replace(/<blockquote>\\s*<p>\\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\\]([\\s\\S]*?)<\\/blockquote>/gi, function(match, type, content) {
              const t = type.toLowerCase();
              return '<div class="alert alert-' + t + '"><div class="alert-title">' + type.toUpperCase() + '</div><p>' + content.trim() + '</div>';
            });

            container.innerHTML = html;
          } else {
            // Line Review Mode with Line Numbers & Inline Comments
            const lines = rawMarkdown.split("\\n");
            let html = '<div class="line-review-table">';
            
            for (let i = 0; i < lines.length; i++) {
              const lineNum = i + 1;
              const lineText = lines[i];
              let lineClass = "line-code";
              if (lineText.startsWith("#")) lineClass += " heading";
              else if (lineText.startsWith("-") || lineText.startsWith("*")) lineClass += " list-item";
              else if (lineText.startsWith(">")) lineClass += " comment";

              html += '<div class="line-row" id="line-row-' + lineNum + '">';
              html += '  <div class="line-gutter">';
              html += '    <span class="has-comment-badge" id="badge-' + lineNum + '" style="display:none;">💬</span>';
              html += '    <span class="line-num" onclick="toggleCommentBox(' + lineNum + ')">' + lineNum + '</span>';
              html += '    <button class="line-add-btn" onclick="toggleCommentBox(' + lineNum + ')" title="Comment on Line ' + lineNum + '">+</button>';
              html += '  </div>';
              html += '  <div class="' + lineClass + '">' + (escapeHtml(lineText) || '&nbsp;') + '</div>';
              html += '</div>';

              // Comment form container
              html += '<div class="comment-box-container" id="box-' + lineNum + '" style="display:none;">';
              html += '  <div class="form-header">💬 Comment on Line ' + lineNum + '</div>';
              html += '  <textarea class="comment-textarea" id="input-' + lineNum + '" placeholder="Write a review comment for line ' + lineNum + '..."></textarea>';
              html += '  <div class="form-actions">';
              html += '    <button class="btn-cancel" onclick="toggleCommentBox(' + lineNum + ')">Cancel</button>';
              html += '    <button class="btn-submit" onclick="submitLineComment(' + lineNum + ')">💬 Add Comment</button>';
              html += '  </div>';
              html += '</div>';

              // Attached comments container
              html += '<div id="thread-' + lineNum + '"></div>';
            }
            html += '</div>';
            container.innerHTML = html;

            // Populate existing line comments
            savedComments.forEach(function(c) {
              renderCommentCard(c);
              const b = document.getElementById("badge-" + c.line);
              if (b) b.style.display = "inline";
            });
          }
        }

        function toggleCommentBox(lineNum) {
          const box = document.getElementById("box-" + lineNum);
          if (!box) return;
          if (box.style.display === "none") {
            box.style.display = "block";
            const input = document.getElementById("input-" + lineNum);
            if (input) input.focus();
          } else {
            box.style.display = "none";
          }
        }

        function submitLineComment(lineNum) {
          const input = document.getElementById("input-" + lineNum);
          if (!input) return;
          const comment = input.value.trim();
          if (!comment) return;

          const row = document.getElementById("line-row-" + lineNum);
          let lineText = "";
          if (row) {
            const codeEl = row.querySelector(".line-code");
            if (codeEl) lineText = codeEl.innerText.trim();
          }

          const payload = {
            action: "addLineComment",
            id: "c-" + Date.now() + "-" + Math.floor(Math.random() * 1000),
            line: lineNum,
            lineContent: lineText,
            comment: comment,
            timestamp: Date.now() / 1000.0,
            formattedDate: new Date().toLocaleTimeString()
          };

          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.reviewer) {
            window.webkit.messageHandlers.reviewer.postMessage(payload);
          }

          renderCommentCard(payload);
          input.value = "";
          toggleCommentBox(lineNum);
          const b = document.getElementById("badge-" + lineNum);
          if (b) b.style.display = "inline";
        }

        function renderCommentCard(c) {
          const thread = document.getElementById("thread-" + c.line);
          if (!thread) return;

          const card = document.createElement("div");
          card.className = "comment-card";
          card.id = "card-" + c.id;
          card.innerHTML = 
            '<div class="card-header">' +
            '  <span class="card-badge">💬 Line ' + c.line + '</span>' +
            '  <span>' + (c.formattedDate || 'Just now') + 
            '    <button class="card-del-btn" onclick="deleteComment(\\'' + c.id + '\\', ' + c.line + ')" title="Delete comment">✕</button>' +
            '  </span>' +
            '</div>' +
            '<div class="card-text">' + escapeHtml(c.comment) + '</div>';
          thread.appendChild(card);
        }

        function deleteComment(id, lineNum) {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.reviewer) {
            window.webkit.messageHandlers.reviewer.postMessage({
              action: "deleteLineComment",
              id: id,
              line: lineNum
            });
          }
          const card = document.getElementById("card-" + id);
          if (card) card.remove();

          const thread = document.getElementById("thread-" + lineNum);
          if (thread && thread.children.length === 0) {
            const b = document.getElementById("badge-" + lineNum);
            if (b) b.style.display = "none";
          }
        }

        function escapeHtml(text) {
          return (text || "")
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#039;");
        }

        window.scrollToLine = function(lineNum) {
          const row = document.getElementById("line-row-" + lineNum);
          if (row) {
            row.scrollIntoView({ behavior: 'smooth', block: 'center' });
            row.style.backgroundColor = "rgba(56, 139, 253, 0.25)";
            setTimeout(() => { row.style.backgroundColor = ""; }, 1500);
          }
        };

        renderView();
        </script>
        </body>
        </html>
        """
        nsView.loadHTMLString(html, baseURL: resourcesDir)
    }
}

// MARK: - SwiftUI Root View
struct ReviewerView: View {
    @ObservedObject var state: ReviewerState
    let resourcesDir: URL
    @State private var showDrawer: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerView
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Color(red: 0.10, green: 0.12, blue: 0.15))
                .overlay(Rectangle().frame(height: 1).foregroundColor(Color(white: 0.2)), alignment: .bottom)

            // Main WebKit View
            MarkdownWebView(state: state, resourcesDir: resourcesDir)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom Review Summary & Commenting Drawer
            if showDrawer {
                drawerSummaryView
                    .padding(12)
                    .background(Color(red: 0.10, green: 0.12, blue: 0.15))
                    .overlay(Rectangle().frame(height: 1).foregroundColor(Color(white: 0.2)), alignment: .top)
            }
        }
        .frame(minWidth: 780, minHeight: 640)
        .background(Color(red: 0.05, green: 0.07, blue: 0.09))
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text("📋")
                    .font(.system(size: 15))
                Text(state.fileName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }

            if state.requestFeedback {
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("Needs Review")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(4)
            } else {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("Reviewed")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.15))
                .cornerRadius(4)
            }

            // View Mode Toggle (Line Review vs Document)
            HStack(spacing: 2) {
                Button(action: { state.viewMode = "line" }) {
                    HStack(spacing: 4) {
                        Text("🔍")
                        Text("Line Review")
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(state.viewMode == "line" ? Color.blue : Color.white.opacity(0.06))
                    .foregroundColor(state.viewMode == "line" ? .white : .gray)
                    .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: { state.viewMode = "rendered" }) {
                    HStack(spacing: 4) {
                        Text("📖")
                        Text("Document")
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(state.viewMode == "rendered" ? Color.blue : Color.white.opacity(0.06))
                    .foregroundColor(state.viewMode == "rendered" ? .white : .gray)
                    .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(2)
            .background(Color.black.opacity(0.2))
            .cornerRadius(5)

            Spacer()

            // Open in External App
            Button(action: {
                if let url = state.fileURL {
                    NSWorkspace.shared.open(url)
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11))
                    Text("Editor")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .foregroundColor(.white.opacity(0.85))
                .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())

            // Reload file
            Button(action: {
                state.loadFile(state.filePath)
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .padding(5)
                    .background(Color.white.opacity(0.08))
                    .foregroundColor(.white.opacity(0.85))
                    .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var drawerSummaryView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Text("💬")
                    Text("Line Comments (\(state.lineComments.count))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer()

                if !state.statusMessage.isEmpty {
                    Text(state.statusMessage)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(state.statusColor)
                }
            }

            if state.lineComments.isEmpty {
                HStack(spacing: 4) {
                    Text("💡 Hover over any line number in the gutter and click")
                        .font(.system(size: 10.5))
                        .foregroundColor(.gray)
                    Text("[+]")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.blue)
                    Text("to leave an inline review comment.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.gray)
                }
                .padding(.vertical, 3)
            } else {
                // List of active line comments with quick jump
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(state.lineComments.sorted(by: { $0.line < $1.line })) { c in
                            HStack(spacing: 5) {
                                Text("L\(c.line):")
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(.cyan)
                                Text(c.comment)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.9))
                                    .lineLimit(1)
                                Button(action: { state.deleteLineComment(id: c.id) }) {
                                    Text("✕")
                                        .font(.system(size: 9))
                                        .foregroundColor(.gray)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(4)
                        }
                    }
                }
            }

            // Action Buttons
            HStack(spacing: 10) {
                Text("All line comments auto-save to feedback.md & sync to clipboard.")
                    .font(.system(size: 9.5))
                    .foregroundColor(.gray)

                Spacer()

                if !state.lineComments.isEmpty {
                    Button(action: { state.syncClipboardWithLineComments(); state.statusMessage = "📋 Copied all comments!"; state.statusColor = .cyan }) {
                        HStack(spacing: 4) {
                            Text("📋")
                            Text("Copy Comments")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Button(action: { state.approveAndProceed() }) {
                    HStack(spacing: 4) {
                        Text("✓")
                        Text(state.requestFeedback ? "Approve & Proceed" : "Approved")
                            .font(.system(size: 10.5, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(state.requestFeedback ? Color.green : Color.gray.opacity(0.4))
                    .foregroundColor(state.requestFeedback ? .black : .white.opacity(0.8))
                    .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!state.requestFeedback)
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - App Delegate & Main
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let state = ReviewerState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let exeURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let rootDir = exeURL.deletingLastPathComponent().deletingLastPathComponent()
        let resourcesDir = rootDir.appendingPathComponent("resources")

        var targetPath: String? = nil
        let args = ProcessInfo.processInfo.arguments
        if args.count > 1 && !args[1].starts(with: "-") {
            targetPath = args[1]
        } else {
            targetPath = findLatestPendingArtifact(rootDir: rootDir)
        }

        guard let path = targetPath, FileManager.default.fileExists(atPath: path) else {
            let alert = NSAlert()
            alert.messageText = "No Artifact Found"
            alert.informativeText = "Could not locate a pending plan or artifact file to review."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        state.loadFile(path)

        let contentView = ReviewerView(state: state, resourcesDir: resourcesDir)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "📋 \(state.fileName) — Antigravity Artifact Reviewer"
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func findLatestPendingArtifact(rootDir: URL) -> String? {
        let artifactsFile = rootDir.appendingPathComponent("state/artifacts.json")
        if FileManager.default.fileExists(atPath: artifactsFile.path),
           let data = try? Data(contentsOf: artifactsFile),
           let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for item in items {
                if let req = item["requestFeedback"] as? Bool, req == true,
                   let p = item["path"] as? String, FileManager.default.fileExists(atPath: p) {
                    return p
                }
            }
            if let first = items.first, let p = first["path"] as? String, FileManager.default.fileExists(atPath: p) {
                return p
            }
        }

        let brainDir = URL(fileURLWithPath: NSString(string: "~/.gemini/antigravity-cli/brain").expandingTildeInPath)
        if FileManager.default.fileExists(atPath: brainDir.path),
           let convs = try? FileManager.default.contentsOfDirectory(at: brainDir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) {
            let sorted = convs.sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                return d1 > d2
            }
            for conv in sorted {
                let planFile = conv.appendingPathComponent("plan.md")
                if FileManager.default.fileExists(atPath: planFile.path) {
                    return planFile.path
                }
            }
        }

        return nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// MARK: - Main Entry Point
@main
struct ArtifactReviewerApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
