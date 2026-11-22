import Foundation

/// A quote found on Wikiquote, ready to save as the week's quote.
struct FoundQuote: Identifiable, Hashable {
    let text: String
    let by: String
    let page: String
    var id: String { page + "\u{1F}" + text }
    var pageURL: URL? {
        let slug = page.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? page
        return URL(string: "https://en.wikiquote.org/wiki/" + slug)
    }
}

/// Quote search on Wikiquote through Wikimedia's public API (no key).
/// Mirrors web/quote-search.js: keep the two alike.
enum QuoteSearch {
    static let maxText = 400, maxBy = 120, maxResults = 40, pages = 4
    private static let api = URL(string: "https://en.wikiquote.org/w/api.php")!
    private static let skip = try! NSRegularExpression(
        pattern: #"^(misattribut|disputed|unsourced|unverified|doubtful|attributed|quotes? (about|regarding|on)\b|about\b|sayings about|external links|see also|sources|references|notes|bibliography|further reading|cast|dialogue|links)"#,
        options: [.caseInsensitive])

    enum Failure: LocalizedError {
        case http(Int), api(String)
        var errorDescription: String? {
            switch self {
            case .http(let code): return "Wikiquote didn't answer (\(code)). Try again in a moment."
            case .api(let info): return info.isEmpty ? "Wikiquote couldn't run that search." : info
            }
        }
    }

    // MARK: Search

    static func search(_ query: String) async throws -> [FoundQuote] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let found: SearchResponse = try await call(["action": "query", "list": "search", "srsearch": q, "srnamespace": "0", "srlimit": "8"])
        let titles = (found.query?.search ?? []).map(\.title).prefix(pages)
        let read: [(Int, Page)] = try await withThrowingTaskGroup(of: (Int, Page).self) { group in
            for (index, title) in titles.enumerated() {
                group.addTask {
                    do {
                        let d: ParseResponse = try await call(["action": "parse", "page": title, "prop": "wikitext|categories", "redirects": "1"])
                        let name = d.parse?.title ?? title
                        return (index, Page(title: name, quotes: quotesFromPage(title: name, wikitext: d.parse?.wikitext ?? "", categories: d.parse?.categories?.map(\.category) ?? [])))
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return (index, Page(title: title, quotes: []))
                    }
                }
            }
            var all: [(Int, Page)] = []
            for try await item in group { all.append(item) }
            return all
        }
        return rank(q, read.sorted { $0.0 < $1.0 }.map(\.1))
    }

    struct Page { let title: String; let quotes: [FoundQuote] }

    private struct SearchResponse: Decodable {
        struct Q: Decodable { let search: [Hit]? }
        struct Hit: Decodable { let title: String }
        let query: Q?
    }
    private struct ParseResponse: Decodable {
        struct P: Decodable { let title: String?; let wikitext: String?; let categories: [C]? }
        struct C: Decodable { let category: String }
        let parse: P?
    }
    private struct APIError: Decodable { struct E: Decodable { let info: String? }; let error: E? }

    private static func call<T: Decodable>(_ params: [String: String]) async throws -> T {
        var parts = URLComponents(url: api, resolvingAgainstBaseURL: false)!
        parts.queryItems = (params.merging(["format": "json", "formatversion": "2"]) { a, _ in a })
            .sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: parts.url!, timeoutInterval: 15)
        request.setValue("Kay2-Do/1.0 (https://tasks.kay2ventures.com)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw Failure.http(http.statusCode) }
        if let err = try? JSONDecoder().decode(APIError.self, from: data), let e = err.error { throw Failure.api(e.info ?? "") }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: Ranking

    static func rank(_ query: String, _ pages: [Page]) -> [FoundQuote] {
        let nq = norm(query)
        let terms = nq.split(separator: " ").map(String.init).filter { $0.count > 2 }
        var seen = Set<String>(), whole: [FoundQuote] = [], matched: [FoundQuote] = [], partial: [FoundQuote] = []
        for page in pages {
            let t = norm(page.title)
            let titleHit = t == nq || t.hasPrefix(nq + " ") || (nq.count > 3 && t.contains(nq))
            for q in page.quotes {
                let key = norm(q.text)
                if seen.contains(key) { continue }
                let hay = norm(q.text + " " + q.by)
                let all = !terms.isEmpty && terms.allSatisfy { hay.contains($0) }
                let any = terms.contains { hay.contains($0) }
                if titleHit { whole.append(q) } else if all { matched.append(q) } else if any { partial.append(q) } else { continue }
                seen.insert(key)
            }
        }
        let best = Array(whole.prefix(30)) + matched
        return Array((best.isEmpty ? partial : best).prefix(maxResults))
    }

    static func norm(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
        let mapped = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    // MARK: Parsing

    static func quotesFromPage(title: String, wikitext: String, categories: [String]) -> [FoundQuote] {
        let cats = categories.map { $0.replacingOccurrences(of: "_", with: " ") }
        if cats.contains(where: { $0.range(of: "disambiguation", options: .caseInsensitive) != nil }) { return [] }
        let person = cats.contains { c in
            let l = c.lowercased()
            return l.contains("births") || l.contains("deaths") || l.contains("living people") || l.hasSuffix("people")
        }
        return parseQuotes(wikitext).compactMap { q in
            let by: String
            if person {
                let src = q.source.isEmpty ? q.section : q.source
                by = !src.isEmpty && (title + ", " + src).count <= maxBy ? title + ", " + src : title
            } else {
                by = q.source
            }
            guard !by.isEmpty else { return nil }
            return FoundQuote(text: q.text, by: String(by.prefix(maxBy)), page: title)
        }
    }

    struct Parsed { var text: String; var source: String; var section: String }

    static func parseQuotes(_ wikitext: String) -> [Parsed] {
        var out: [Parsed] = []
        var skipH2 = false, skipH3 = false, section = ""
        var lastIndex: Int?
        var poem: (lines: [String], section: String)?

        func add(_ body: String, _ sec: String) -> Int {
            out.append(Parsed(text: clean(body), source: "", section: sec))
            return out.count - 1
        }

        for raw in wikitext.components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
            if var p = poem {
                if let end = line.range(of: "</poem>", options: .caseInsensitive) {
                    p.lines.append(String(line[..<end.lowerBound]))
                    let text = p.lines.map(clean).filter { !$0.isEmpty }.joined(separator: " / ")
                    lastIndex = add(text, p.section)
                    poem = nil
                } else {
                    p.lines.append(line)
                    poem = p
                }
                continue
            }
            if let heading = headingMatch(line) {
                let title = clean(heading.title)
                if heading.level == 2 { skipH2 = matchesSkip(title); skipH3 = false; section = "" }
                else { skipH3 = matchesSkip(title); section = title }
                lastIndex = nil
                continue
            }
            if skipH2 || skipH3 { continue }
            if line.range(of: #"^\*[^*:#]"#, options: .regularExpression) != nil {
                let body = line.replacingOccurrences(of: #"^\*\s*"#, with: "", options: .regularExpression)
                if body.range(of: "<poem>", options: .caseInsensitive) != nil, body.range(of: "</poem>", options: .caseInsensitive) == nil {
                    let start = body.range(of: "<poem>", options: .caseInsensitive)!
                    poem = ([String(body[start.upperBound...])], section)
                    continue
                }
                lastIndex = add(body, section)
            } else if line.range(of: #"^\*\*[^*]"#, options: .regularExpression) != nil, let i = lastIndex, out[i].source.isEmpty {
                out[i].source = clean(line.replacingOccurrences(of: #"^\*\*\s*"#, with: "", options: .regularExpression))
            } else if !line.hasPrefix("**"), !line.hasPrefix(":"), !line.hasPrefix("#") {
                lastIndex = nil
            }
        }
        return out.filter { $0.text.count >= 8 && $0.text.count <= maxText }
    }

    private static func headingMatch(_ line: String) -> (level: Int, title: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(={2,6})\s*(.*?)\s*\1\s*$"#),
              let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let eq = Range(m.range(at: 1), in: line), let t = Range(m.range(at: 2), in: line) else { return nil }
        return (line[eq].count, String(line[t]))
    }

    private static func matchesSkip(_ title: String) -> Bool {
        skip.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil
    }

    /// Wiki markup → plain text.
    static func clean(_ s: String) -> String {
        var t = s
        func sub(_ pattern: String, _ template: String, _ opts: NSRegularExpression.Options = [.caseInsensitive]) {
            guard let r = try? NSRegularExpression(pattern: pattern, options: opts) else { return }
            t = r.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: template)
        }
        sub(#"<!--[\s\S]*?-->"#, "")
        sub(#"<ref[^>]*/>"#, "")
        sub(#"<ref[^>]*>[\s\S]*?</ref>"#, "")
        sub(#"<br\s*/?>"#, " / ")
        // Templates, innermost first: keep the text of {{w|…}}, {{lang|…|text}} and the like.
        let template = try! NSRegularExpression(pattern: #"\{\{([^{}]*)\}\}"#)
        for _ in 0..<5 {
            let ns = t as NSString
            let matches = template.matches(in: t, range: NSRange(location: 0, length: ns.length))
            if matches.isEmpty { break }
            var result = ""
            var cursor = 0
            for m in matches {
                result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                let parts = ns.substring(with: m.range(at: 1)).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                let name = parts[0].lowercased()
                if (name == "w" || name == "wikipedia"), parts.count > 1 { result += parts.count > 2 ? parts[2] : parts[1] }
                else if (name == "lang" || name == "lang-x"), parts.count > 2 { result += parts[2] }
                else if ["small", "nowrap", "smallcaps"].contains(name), parts.count > 1 { result += parts[1] }
                cursor = m.range.location + m.range.length
            }
            result += ns.substring(from: cursor)
            t = result
        }
        sub(#"\[\[(?:file|image|category):[^\]]*\]\]"#, "")
        sub(#"\[\[([^\]|]*)\|([^\]]*)\]\]"#, "$2", [])
        sub(#"\[\[(?:w|wikipedia|s|wikisource):([^\]]*)\]\]"#, "$1")
        sub(#"\[\[([^\]]*)\]\]"#, "$1", [])
        sub(#"\[(?:https?:)?//\S+\s+([^\]]+)\]"#, "$1")
        sub(#"\[(?:https?:)?//[^\]]*\]"#, "")
        sub(#"'''''|'''|''"#, "", [])
        sub(#"</?[a-z][^>]*>"#, "")
        for (a, b) in [("&nbsp;", " "), ("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&mdash;", "—"), ("&ndash;", "–")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
