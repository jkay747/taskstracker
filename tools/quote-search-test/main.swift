// Checks apple/Kay2Do/QuoteSearch.swift: the parser on saved sample pages, then a few
// live searches on Wikiquote. Run from the repo root:
//   swiftc apple/Kay2Do/QuoteSearch.swift tools/quote-search-test/main.swift -o /tmp/qst && /tmp/qst
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print((ok ? "ok   " : "FAIL ") + what)
    if !ok { failures += 1 }
}

let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "tools/quote-search-test")
let rumi = try String(contentsOf: dir.appendingPathComponent("sample-rumi.txt"), encoding: .utf8)
let courage = try String(contentsOf: dir.appendingPathComponent("sample-courage.txt"), encoding: .utf8)

let r = QuoteSearch.quotesFromPage(title: "Rumi", wikitext: rumi, categories: ["1207_births", "Persian_poets"])
check(r.count == 4, "Rumi sample: 4 quotes (got \(r.count))")
check(r.first?.text == "Pain is a treasure, for it contains mercies.", "first quote, reference removed")
check(r.first?.by == "Rumi, Book III, as translated by E. H. Whinfield", "source line becomes the attribution")
check(r.count > 1 && r[1].text == "Let the beauty of what you love be what you do." && r[1].by == "Rumi, Coleman Barks translation", "italics and {{w|…}} cleaned")
check(r.count > 2 && r[2].text == "Out beyond ideas of wrongdoing and rightdoing, / there is a field. I'll meet you there." && r[2].by == "Rumi, Masnavi", "one-line poem, section as source")
check(r.count > 3 && r[3].text == "When the soul lies down in that grass, / the world is too full to talk about." && r[3].by == "Rumi, The Essential Rumi", "multi-line poem")
check(!r.contains { $0.text.contains("Disputed") || $0.text.contains("clever") || $0.text.contains("Rumi is great") }, "disputed, misattributed and about sections skipped")

let c = QuoteSearch.quotesFromPage(title: "Courage", wikitext: courage, categories: ["Virtues"])
check(c.count == 2, "Courage sample: 2 attributed quotes (got \(c.count))")
check(c.first?.by == "Maya Angelou, interview in USA Today (5 March 1988)", "topic page: speaker from the line under the quote")
check(QuoteSearch.quotesFromPage(title: "X", wikitext: rumi, categories: ["Disambiguation_pages"]).isEmpty, "disambiguation pages give nothing")

let pages = [QuoteSearch.Page(title: "Rumi", quotes: r), QuoteSearch.Page(title: "Courage", quotes: c)]
check(QuoteSearch.rank("rumi", pages).count == 4, "a search named like a page gives that page's quotes")
check(QuoteSearch.rank("courage grow", pages).map(\.text) == ["It takes courage to grow up and become who you really are."], "keyword search keeps quotes with every word")
check(QuoteSearch.clean("He said {{lang|fr|bonjour}} &amp; [[w:Paris|the city]]<br/>then [http://x.com link] '''left'''") == "He said bonjour & the city / then link left", "markup cleaned")

print("\nLive searches on Wikiquote:")
let live = ["Rumi", "Alan Watts", "courage", "Maya Angelou"]
var liveTotal = 0
for term in live {
    do {
        let found = try await QuoteSearch.search(term)
        liveTotal += found.count
        print("  \(term): \(found.count) quotes")
        for q in found.prefix(3) { print("    “\(q.text.prefix(90))” — \(q.by)") }
    } catch {
        print("  \(term): error \(error.localizedDescription)")
    }
}
check(liveTotal > 0, "live searches found quotes")

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
