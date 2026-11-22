// Checks web/quote-search.js the same way main.swift checks the app's version.
// Run from the repo root: node tools/quote-search-test/test.js
const fs = require("fs"), path = require("path");
const QS = require(path.resolve("web/quote-search.js"));
const { clean, quotesFromPage, rank } = QS._test;
const dir = path.resolve("tools/quote-search-test");
let failures = 0;
const check = (ok, what) => { console.log((ok ? "ok   " : "FAIL ") + what); if (!ok) failures++; };

const r = quotesFromPage("Rumi", fs.readFileSync(path.join(dir, "sample-rumi.txt"), "utf8"), [{ category: "1207_births" }]);
const c = quotesFromPage("Courage", fs.readFileSync(path.join(dir, "sample-courage.txt"), "utf8"), [{ category: "Virtues" }]);
check(r.length === 4, "Rumi sample: 4 quotes (got " + r.length + ")");
check(r[0] && r[0].by === "Rumi, Book III, as translated by E. H. Whinfield", "source line becomes the attribution");
check(r[3] && r[3].text === "When the soul lies down in that grass, / the world is too full to talk about.", "multi-line poem");
check(c.length === 2 && c[0].by === "Maya Angelou, interview in USA Today (5 March 1988)", "topic page: speaker from the line under the quote");
check(rank("courage grow", [{ title: "Rumi", quotes: r }, { title: "Courage", quotes: c }]).length === 1, "keyword search keeps quotes with every word");
check(clean("He said {{lang|fr|bonjour}} &amp; [[w:Paris|the city]]<br/>then [http://x.com link] '''left'''") === "He said bonjour & the city / then link left", "markup cleaned");

(async () => {
  console.log("\nLive searches on Wikiquote:");
  let total = 0;
  for (const term of ["Rumi", "Alan Watts", "courage", "Maya Angelou"]) {
    try {
      const found = await QS.search(term);
      total += found.length;
      console.log("  " + term + ": " + found.length + " quotes");
      found.slice(0, 3).forEach(q => console.log("    “" + q.text.slice(0, 90) + "” — " + q.by));
    } catch (e) { console.log("  " + term + ": error " + e.message); }
  }
  check(total > 0, "live searches found quotes");
  console.log(failures ? "\n" + failures + " check(s) failed." : "\nAll checks passed.");
  process.exit(failures ? 1 : 0);
})();
