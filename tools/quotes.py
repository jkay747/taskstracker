"""The built-in weekly quotes, shared by the web and Apple apps.

Every quote is from a public-domain text (author or translator long dead, or
published before 1929), so the app can be shared or sold freely. Writers
still under copyright (Alan Watts, Coleman Barks's Rumi, Daniel Ladinsky's
Hafiz, Mary Oliver...) are left out; type their words in as your own quote
for the week instead.

Run `python3 tools/quotes.py` after editing to regenerate:
  web/quotes.js and apple/Kay2Do/Quotes.swift
"""
import json, pathlib

QUOTES = [
    ("Pain is a treasure, for it contains mercies.", "Rumi", "Masnavi, tr. E. H. Whinfield"),
    ("Love depends not on outward form or face.", "Rumi", "Masnavi, tr. E. H. Whinfield"),
    ("Be silent that the Lord who gave thee language may speak.", "Rumi", "Divani Shamsi Tabriz, tr. R. A. Nicholson"),
    ("The spring seasons are hidden in the autumns.", "Rumi", "Masnavi, tr. E. H. Whinfield"),
    ("Trust thyself: every heart vibrates to that iron string.", "Ralph Waldo Emerson", "Self-Reliance"),
    ("Nothing great was ever achieved without enthusiasm.", "Ralph Waldo Emerson", "Circles"),
    ("Hitch your wagon to a star.", "Ralph Waldo Emerson", "Civilization"),
    ("Write it on your heart that every day is the best day in the year.", "Ralph Waldo Emerson", "Works and Days"),
    ("Nothing can bring you peace but yourself.", "Ralph Waldo Emerson", "Self-Reliance"),
    ("Our life is frittered away by detail. … Simplify, simplify.", "Henry David Thoreau", "Walden"),
    ("I went to the woods because I wished to live deliberately, to front only the essential facts of life.", "Henry David Thoreau", "Walden"),
    ("If one advances confidently in the direction of his dreams, and endeavors to live the life which he has imagined, he will meet with a success unexpected in common hours.", "Henry David Thoreau", "Walden"),
    ("Heaven is under our feet as well as over our heads.", "Henry David Thoreau", "Walden"),
    ("Not till we are lost … do we begin to find ourselves.", "Henry David Thoreau", "Walden"),
    ("Every morning was a cheerful invitation to make my life of equal simplicity, and I may say innocence, with Nature herself.", "Henry David Thoreau", "Walden"),
    ("Rather than love, than money, than fame, give me truth.", "Henry David Thoreau", "Walden"),
    ("I am large, I contain multitudes.", "Walt Whitman", "Song of Myself"),
    ("I exist as I am, that is enough.", "Walt Whitman", "Song of Myself"),
    ("Afoot and light-hearted I take to the open road.", "Walt Whitman", "Song of the Open Road"),
    ("Work is love made visible.", "Kahlil Gibran", "The Prophet"),
    ("The deeper that sorrow carves into your being, the more joy you can contain.", "Kahlil Gibran", "The Prophet"),
    ("Forget not that the earth delights to feel your bare feet and the winds long to play with your hair.", "Kahlil Gibran", "The Prophet"),
    ("Let there be spaces in your togetherness.", "Kahlil Gibran", "The Prophet"),
    ("Trees are poems that the earth writes upon the sky.", "Kahlil Gibran", "Sand and Foam"),
    ("You can not cross the sea merely by standing and staring at the water.", "Rabindranath Tagore", "Stray Birds"),
    ("Let life be beautiful like summer flowers and death like autumn leaves.", "Rabindranath Tagore", "Stray Birds"),
    ("Clouds come floating into my life, no longer to carry rain or usher storm, but to add color to my sunset sky.", "Rabindranath Tagore", "Stray Birds"),
    ("Faith is the bird that feels the light and sings when the dawn is still dark.", "Rabindranath Tagore", "Fireflies"),
    ("Let me not pray to be sheltered from dangers but to be fearless in facing them.", "Rabindranath Tagore", "Fruit-Gathering"),
    ("I laugh when I hear that the fish in the water is thirsty.", "Kabir", "Songs of Kabir, tr. Rabindranath Tagore"),
    ("All that we are is the result of what we have thought.", "The Buddha", "Dhammapada, tr. F. Max Müller"),
    ("Hatred does not cease by hatred at any time: hatred ceases by love.", "The Buddha", "Dhammapada, tr. F. Max Müller"),
    ("The journey of a thousand li commenced with a single step.", "Lao Tzu", "Tao Te Ching, tr. James Legge"),
    ("He who knows other men is discerning; he who knows himself is intelligent.", "Lao Tzu", "Tao Te Ching, tr. James Legge"),
    ("The highest excellence is like that of water.", "Lao Tzu", "Tao Te Ching, tr. James Legge"),
    ("When we see men of worth, we should think of equalling them.", "Confucius", "Analects, tr. James Legge"),
    ("Look within. Within is the fountain of good, and it will ever bubble up, if thou wilt ever dig.", "Marcus Aurelius", "Meditations, tr. George Long"),
    ("No longer talk at all about the kind of man that a good man ought to be, but be such.", "Marcus Aurelius", "Meditations, tr. George Long"),
    ("Men are disturbed, not by things, but by the principles and notions which they form concerning things.", "Epictetus", "Enchiridion, tr. Elizabeth Carter"),
    ("While we are postponing, life speeds by.", "Seneca", "Letters to Lucilius, tr. R. M. Gummere"),
    ("We suffer more often in imagination than in reality.", "Seneca", "Letters to Lucilius, tr. R. M. Gummere"),
    ("You cannot step twice into the same rivers; for fresh waters are ever flowing in upon you.", "Heraclitus", "tr. John Burnet"),
    ("In every walk with nature one receives far more than he seeks.", "John Muir", "Steep Trails"),
    ("The mountains are calling & I must go.", "John Muir", "Letter to his sister, 1873"),
    ("Let nothing disturb thee, nothing affright thee; all things are passing.", "Teresa of Ávila", "tr. Henry Wadsworth Longfellow"),
    ("All shall be well, and all shall be well, and all manner of thing shall be well.", "Julian of Norwich", "Revelations of Divine Love"),
    ("To see a World in a Grain of Sand / And a Heaven in a Wild Flower.", "William Blake", "Auguries of Innocence"),
    ("“Hope” is the thing with feathers – that perches in the soul.", "Emily Dickinson", "Poem 254"),
    ("This above all: to thine own self be true.", "William Shakespeare", "Hamlet"),
    ("To be great is to be misunderstood.", "Ralph Waldo Emerson", "Self-Reliance"),
    ("The only gift is a portion of thyself.", "Ralph Waldo Emerson", "Gifts"),
    ("Re-examine all you have been told at school or church or in any book, dismiss whatever insults your own soul.", "Walt Whitman", "Preface to Leaves of Grass, 1855"),
]

# Spread authors out so the same writer doesn't come up two weeks running.
def interleave(items):
    groups = {}
    for q in items:
        groups.setdefault(q[1], []).append(q)
    order = sorted(groups.values(), key=len, reverse=True)
    out = []
    while any(order):
        for g in order:
            if g:
                out.append(g.pop(0))
    return out

root = pathlib.Path(__file__).resolve().parent.parent
qs = interleave(QUOTES)
assert len(qs) == len(set(q[0] for q in qs))
js = "// Generated by tools/quotes.py. Edit that file, not this one.\nwindow.KAY2DO_QUOTES = " + json.dumps(
    [{"text": t, "by": b, "source": s} for t, b, s in qs], ensure_ascii=False, indent=1) + ";\n"
(root / "web/quotes.js").write_text(js)
lines = ["// Generated by tools/quotes.py. Edit that file, not this one.", "", "enum Quotes {", "    static let all: [Quote] = ["]
for t, b, s in qs:
    lines.append(f"        Quote(text: {json.dumps(t, ensure_ascii=False)}, by: {json.dumps(b, ensure_ascii=False)}, source: {json.dumps(s, ensure_ascii=False)}),")
lines += ["    ]", "}", ""]
(root / "apple/Kay2Do/Quotes.swift").write_text("\n".join(lines))
print(len(qs), "quotes")
