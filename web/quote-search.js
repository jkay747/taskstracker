// Quote search on Wikiquote (en.wikiquote.org), through Wikimedia's public API.
// No key needed, and the API allows calls straight from the browser. The Mac and
// iPhone app do the same thing in apple/Kay2Do/QuoteSearch.swift: keep the two alike.
(function () {
  "use strict";
  const API = "https://en.wikiquote.org/w/api.php";
  const MAX_TEXT = 400, MAX_BY = 120, MAX_RESULTS = 40, PAGES = 4;
  // Sections that hold no real quotes from the page's subject.
  const SKIP = /^(misattribut|disputed|unsourced|unverified|doubtful|attributed|quotes? (about|regarding|on)\b|about\b|sayings about|external links|see also|sources|references|notes|bibliography|further reading|cast|dialogue|links)/i;

  async function api(params, signal) {
    const url = new URL(API);
    Object.entries(Object.assign({}, params, { format: "json", formatversion: "2", origin: "*" }))
      .forEach(([k, v]) => url.searchParams.set(k, v));
    const res = await fetch(url, { signal, headers: { "Api-User-Agent": "Kay2-Do/1.0 (https://tasks.kay2ventures.com)" } });
    if (!res.ok) throw new Error("Wikiquote didn't answer (" + res.status + "). Try again in a moment.");
    const data = await res.json();
    if (data.error) throw new Error(data.error.info || "Wikiquote couldn't run that search.");
    return data;
  }

  // Wiki markup → plain text.
  function clean(s) {
    let t = String(s);
    t = t.replace(/<!--[\s\S]*?-->/g, "");
    t = t.replace(/<ref[^>]*\/>/gi, "").replace(/<ref[^>]*>[\s\S]*?<\/ref>/gi, "");
    t = t.replace(/<br\s*\/?>/gi, " / ");
    for (let i = 0; i < 5 && /\{\{[^{}]*\}\}/.test(t); i++) {
      t = t.replace(/\{\{([^{}]*)\}\}/g, (m, inner) => {
        const parts = inner.split("|").map(x => x.trim());
        const name = parts[0].toLowerCase();
        if ((name === "w" || name === "wikipedia") && parts[1]) return parts[2] || parts[1];
        if ((name === "lang" || name === "lang-x") && parts[2]) return parts[2];
        if (name === "small" || name === "nowrap" || name === "smallcaps") return parts[1] || "";
        return "";
      });
    }
    t = t.replace(/\[\[(?:file|image|category):[^\]]*\]\]/gi, "");
    t = t.replace(/\[\[([^\]|]*)\|([^\]]*)\]\]/g, "$2");
    t = t.replace(/\[\[([^\]]*)\]\]/g, (m, x) => x.replace(/^(w|wikipedia|s|wikisource):/i, ""));
    t = t.replace(/\[(?:https?:)?\/\/\S+\s+([^\]]+)\]/g, "$1").replace(/\[(?:https?:)?\/\/[^\]]*\]/g, "");
    t = t.replace(/'''''|'''|''/g, "");
    t = t.replace(/<\/?[a-z][^>]*>/gi, "");
    t = t.replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&quot;/g, "\"").replace(/&#39;/g, "'").replace(/&mdash;/g, "—").replace(/&ndash;/g, "–");
    return t.replace(/\s+/g, " ").trim();
  }

  // A page's wikitext → [{text, source, section}]. Quotes are the top-level
  // "* " bullets; the first "** " bullet under one says where it's from.
  function parseQuotes(wikitext) {
    const out = [];
    let skipH2 = false, skipH3 = false, section = "", last = null, poem = null;
    for (const raw of String(wikitext).split("\n")) {
      const line = raw.replace(/\s+$/, "");
      if (poem) {
        if (/<\/poem>/i.test(line)) { poem.lines.push(line.replace(/<\/poem>[\s\S]*/i, "")); finishPoem(); }
        else poem.lines.push(line);
        continue;
      }
      const h = line.match(/^(={2,6})\s*(.*?)\s*\1\s*$/);
      if (h) {
        const title = clean(h[2]);
        if (h[1].length === 2) { skipH2 = SKIP.test(title); skipH3 = false; section = ""; }
        else { skipH3 = SKIP.test(title); section = title; }
        last = null;
        continue;
      }
      if (skipH2 || skipH3) continue;
      if (/^\*[^*:#]/.test(line)) {
        const body = line.replace(/^\*\s*/, "");
        if (/<poem>/i.test(body) && !/<\/poem>/i.test(body)) {
          poem = { lines: [body.replace(/^[\s\S]*?<poem>/i, "")], section };
          continue;
        }
        last = add(body, section);
      } else if (/^\*\*[^*]/.test(line) && last && !last.source) {
        last.source = clean(line.replace(/^\*\*\s*/, ""));
      } else if (!/^\*\*/.test(line) && !/^[:#]/.test(line)) {
        last = null;
      }
    }
    return out.filter(q => q.text.length >= 8 && q.text.length <= MAX_TEXT);

    function add(body, sec) {
      const q = { text: clean(body), source: "", section: sec };
      out.push(q);
      return q;
    }
    function finishPoem() {
      const text = poem.lines.map(l => clean(l)).filter(Boolean).join(" / ");
      last = add(text, poem.section);
      poem = null;
    }
  }

  const norm = s => String(s).toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9 ]+/g, " ").replace(/\s+/g, " ").trim();

  function isPerson(categories) {
    return (categories || []).some(c => /births|deaths|living people|people$/i.test(String(c.category || c).replace(/_/g, " ")));
  }
  function isDisambiguation(categories) {
    return (categories || []).some(c => /disambiguation/i.test(String(c.category || c)));
  }

  // One page → quotes with who said them, ready to save.
  function quotesFromPage(title, wikitext, categories) {
    if (isDisambiguation(categories)) return [];
    const person = isPerson(categories);
    return parseQuotes(wikitext).map(q => {
      let by;
      if (person) {
        const src = q.source || q.section;
        by = src && (title + ", " + src).length <= MAX_BY ? title + ", " + src : title;
      } else {
        by = q.source; // theme pages name the speaker in the line under each quote
      }
      return { text: q.text, by: (by || "").slice(0, MAX_BY), source: q.source, page: title, person };
    }).filter(q => q.by);
  }

  // Finds pages matching the words, reads the top few, and keeps the quotes that fit.
  // A page named like the search (a person or a topic) gives all its quotes.
  function rank(query, pages) {
    const nq = norm(query), terms = nq.split(" ").filter(w => w.length > 2);
    const seen = new Set(), whole = [], matched = [], partial = [];
    for (const p of pages) {
      const titleHit = norm(p.title) === nq || norm(p.title).startsWith(nq + " ") || (nq.length > 3 && norm(p.title).includes(nq));
      for (const q of p.quotes) {
        const key = norm(q.text);
        if (seen.has(key)) continue;
        const hay = norm(q.text + " " + q.by);
        const all = terms.length > 0 && terms.every(t => hay.includes(t));
        const any = terms.some(t => hay.includes(t));
        if (titleHit) whole.push(q); else if (all) matched.push(q); else if (any) partial.push(q); else continue;
        seen.add(key);
      }
    }
    const best = whole.slice(0, 30).concat(matched);
    return (best.length ? best : partial).slice(0, MAX_RESULTS);
  }

  async function search(query, signal) {
    const q = String(query || "").trim();
    if (!q) return [];
    const found = await api({ action: "query", list: "search", srsearch: q, srnamespace: "0", srlimit: "8" }, signal);
    const titles = ((found.query && found.query.search) || []).map(r => r.title).slice(0, PAGES);
    const pages = await Promise.all(titles.map(async title => {
      try {
        const d = await api({ action: "parse", page: title, prop: "wikitext|categories", redirects: "1" }, signal);
        const p = d.parse || {};
        return { title: p.title || title, quotes: quotesFromPage(p.title || title, p.wikitext || "", p.categories) };
      } catch (e) {
        if (e && e.name === "AbortError") throw e;
        return { title, quotes: [] };
      }
    }));
    return rank(q, pages);
  }

  const pageUrl = title => "https://en.wikiquote.org/wiki/" + encodeURIComponent(String(title).replace(/ /g, "_"));

  const api_ = { search, pageUrl, _test: { clean, parseQuotes, quotesFromPage, rank } };
  if (typeof window !== "undefined") window.Kay2DoQuoteSearch = api_;
  if (typeof module !== "undefined") module.exports = api_;
})();
