# Kay2-Do

One task tracker, three ways in, one shared list:

| | Where | What it is |
| --- | --- | --- |
| **Web** | `web/` | The planner-sheet list in any browser, published with GitHub Pages |
| **Mac + iPhone** | `apple/` | A native SwiftUI app (one codebase for both) |
| **Data** | `supabase/` | The shared database both of them use |

A task you add on your iPhone shows up on the web page within seconds, and the other way round. Everyone signs in with their email (an emailed sign-in link, no password), and you share a list by inviting someone's email address.

Features, everywhere:

- Categories (rename, recolor, reorder, add up to 12)
- Tasks with due dates, notes, a star for top priority, an owner and other people on the task
- A weekly theme line ("This week will be… because…"), a weekly quote, and a top-three priorities panel
- Search, an owner filter (Everyone / Mine / Unassigned / a person) and a show-completed switch
- A background picture, built-in or your own photo (web and Mac)
- Several lists per account, each shared with its own people
- Roles: **owner** (everything, including who's on the list), **editor** (anything but people), **contributor** (adds tasks; checks off and edits the ones they own, are on, or created)

## Set up

This repo is already connected to its Supabase project (`qgeyztbxylsuihpzpnlb`, named taskstracker): the URL and publishable key are in `web/config.js` and `apple/Kay2Do/SupabaseConfig.swift`. To point it at a different project, change those two files.

### 1. Supabase (done for this project)

1. **SQL Editor → New query**: run all of [`supabase/schema.sql`](supabase/schema.sql). It's safe to run again after changes.
2. **Authentication → URL Configuration**: Site URL `https://jkay747.github.io/taskstracker/`; redirect URLs `kay2do://login`, `https://jkay747.github.io/taskstracker/**` and `http://localhost:8000/**`.

Sign-in works with Supabase's built-in email sender, which sends a **link** and allows only a few emails an hour. Tapping the link on an iPhone or Mac with the app installed opens the app signed in; in a browser it opens the web list signed in. Open the link on the same device you're signing in on.

Optional: for more emails, or to also get a 6-digit code (handy when the email is on a different device), add your own sender under **Authentication → Emails → SMTP Settings**, then add `{{ .Token }}` to the **Magic link** and **Confirm sign up** templates. Both apps already accept the code.

### 2. The keys

The publishable key is meant to be public: row-level security in the schema is what keeps each list private. Never put the `service_role` / secret key in either app.

### 3. Publish the web page

1. On GitHub: **Settings → Pages → Build and deployment → Source: GitHub Actions**.
2. Push to `main`. The **Web app** workflow publishes `web/` to <https://jkay747.github.io/taskstracker/>.

To try it locally instead, run `python3 -m http.server -d web 8000` and open <http://localhost:8000> (already in Supabase's redirect URLs).

### 4. Build the Mac and iPhone app

Needs Xcode 16 or later. A free Apple account is enough to run it on your own Mac or iPhone; TestFlight and the App Store need the paid Developer Program.

1. Open `apple/Kay2Do.xcodeproj`.
2. Select the **Kay2Do** target → **Signing & Capabilities** → choose your **Team**. Change the bundle identifier if Xcode says it's taken.
3. Pick **My Mac** or your iPhone and press **Run**.

### 4b. TestFlight (automatic iPhone builds)

`.github/workflows/testflight.yml` archives the iPhone app, signs it and uploads it to TestFlight every time `apple/` changes on `main`. You can also run it by hand: **Actions → iPhone app to TestFlight → Run workflow**. Until the four secrets below exist it skips itself. Needs the paid Apple Developer Program.

One-time setup:

1. **Create the app in App Store Connect.** appstoreconnect.apple.com → **Apps → + → New App**: platform **iOS**, name **Kay2-Do** (or any name that's free), bundle ID **com.kay2ventures.Kay2Do**, SKU `kay2do`. If the bundle ID isn't in the list, register it first at developer.apple.com → **Certificates, IDs & Profiles → Identifiers → +** (App ID, explicit, `com.kay2ventures.Kay2Do`).
2. **Create an API key.** App Store Connect → **Users and Access → Integrations → App Store Connect API → Team Keys → +**. Access: **Admin** (signing in the cloud needs it). Download the `.p8` file (Apple only lets you download it once) and note the **Key ID** and the **Issuer ID** shown above the list.
3. **Find your Team ID**: developer.apple.com → **Account → Membership details**.
4. **Add four repository secrets**: GitHub repo → **Settings → Secrets and variables → Actions → New repository secret**:
   - `APPLE_TEAM_ID`: the Team ID
   - `ASC_KEY_ID`: the Key ID
   - `ASC_ISSUER_ID`: the Issuer ID
   - `ASC_KEY_P8`: open the `.p8` file in TextEdit and paste the whole thing, including the `BEGIN` and `END` lines
5. Run the workflow once from the Actions tab. When it finishes, the build shows up in App Store Connect → **TestFlight** after Apple's processing (5–15 minutes). Add yourself under **Internal Testing** and install it with the **TestFlight** app on your iPhone.

Build numbers come from the workflow's run number (101, 102, …), so each upload is newer than the last. Change `MARKETING_VERSION` in the project when you want a new version number (1.1, 2.0…).

### 5. Sign in and bring over the old web list

Sign in once (web or app) with your email. You'll land on "Create my list". To bring over the tasks from the old Claude-hosted "Jason Kay To Dos" page instead, run the one-time import SQL in the SQL Editor, then reload.

## Weekly quote

Each list shows a quote under the weekly theme. By default it's a built-in pick that changes every Monday and is the same for everyone on the list: 52 lines from Rumi, Emerson, Thoreau, Whitman, Gibran, Tagore, Lao Tzu, Marcus Aurelius, Seneca, John Muir and others. Owners and editors can press **Change quote** to search for a quote online, step through the picks or type their own, and can turn quotes off under List settings.

**Find a quote online** searches [Wikiquote](https://en.wikiquote.org) through Wikimedia's public API (no key, called straight from the page or the app). Type a person ("Rumi", "Alan Watts") or a topic ("courage"); picking a result fills in the quote and who said it, ready to edit and save. The code is `web/quote-search.js` for the web and `apple/Kay2Do/QuoteSearch.swift` for the app; keep the two alike. `tools/quote-search-test/` checks both on saved sample pages and with a few live searches, and runs on GitHub with the app build.

The built-in quotes are all from public-domain texts or translations, so the app can be shared or sold. Writers still under copyright (Alan Watts, for example) aren't built in; type their words in as the week's quote. To edit the library, change `tools/quotes.py` and run `python3 tools/quotes.py`, which regenerates `web/quotes.js` and `apple/Kay2Do/Quotes.swift`.

## Background picture (web and Mac)

Owners and editors can put a picture behind the list under **List settings → Background picture**: one of 14 built-in public-domain pictures (Hokusai, Van Gogh, Monet, Friedrich, Aivazovsky, Bierstadt, Moran, Ansel Adams's National Park Service work, and NASA/Hubble photos, served by Wikimedia Commons), or a photo you upload. **Photo** sets how strongly it shows through: Subtle, Balanced or Vivid. Everyone on the list sees it on the web and in the Mac app; the iPhone app doesn't show backgrounds.

Uploads are shrunk to at most 3840 pixels on the long side and stored in the private `backgrounds` bucket in Supabase Storage, in a folder for the list. Only people on the list can see them, and only owners and editors can add or remove them. A replaced photo is deleted.

In the Mac app's **Desktop** menu, **Use the List's Picture as the Desktop Picture** fills the screen with it behind the desktop list.

To change the built-in pictures, edit `tools/backgrounds.py` and run `python3 tools/backgrounds.py`, which regenerates `web/backgrounds.js` and `apple/Kay2Do/Backgrounds.swift`. Use only public-domain files, and only Wikimedia's standard thumbnail widths (500, 1920, 3840).

## Sharing a list

1. **List settings → People**: type their email, pick **Contributor** or **Editor**, and press **Invite**.
2. Use **Copy invite message** (web) or **Send Invite Message** (app) and send it to them. Supabase doesn't send an email by itself at this point.
3. They open the web page or the app, sign in with that email, and tap the link in the email. The list is there, and any task you assigned to their email address is now linked to them.

You can assign a task to a typed name or email before someone has joined. It shows as "not linked" until they do.

## Layout

| Path | What it is |
| --- | --- |
| `supabase/schema.sql` | Tables, row-level security, and the functions both apps call (`create_list`, `invite_member`, `accept_invites`, `list_people`) |
| `web/index.html` | The whole web app (HTML, CSS, JS); uses supabase-js from a CDN and live updates |
| `web/config.js` | Supabase URL and anon key for the web app |
| `apple/Kay2Do/Backend.swift` | Small Supabase client: email-link (or code) sign-in, token refresh, REST calls |
| `apple/Kay2Do/Store.swift` | The app's data: loading, refreshing every 12 seconds, saving changes in order |
| `apple/Kay2Do/Model.swift` | Task, category, list and person records, matching the database |
| `apple/Kay2Do/SignInView.swift` | Connect, sign-in and "no list yet" screens |
| `apple/Kay2Do/ContentView.swift` | Sidebar |
| `apple/Kay2Do/TaskListView.swift`, `TaskRow.swift` | The list |
| `apple/Kay2Do/TaskEditor.swift` | Task detail sheet |
| `apple/Kay2Do/SettingsView.swift` | Your name, text look, list name, categories, people |
| `web/quote-search.js`, `apple/Kay2Do/QuoteSearch.swift` | Quote search on Wikiquote, for the web page and the app |
| `apple/Kay2Do/TextAppearance.swift` | Font (system font picker), font size and font color for tasks, saved per device |
| `.github/workflows/build.yml` | Compiles the Mac and iOS builds when `apple/` changes |
| `.github/workflows/testflight.yml` | Archives, signs and uploads the iPhone app to TestFlight when `apple/` changes on `main` |
| `.github/workflows/pages.yml` | Publishes `web/` to GitHub Pages when it changes on `main` |

## Not done yet

- Reminders/notifications for due dates, widgets, Siri/Shortcuts
- The app refreshes on a 12-second timer rather than with live updates (the web page is live)
- Works online only; the app doesn't keep an offline copy
- App Store needs: privacy policy, screenshots, a designed icon, and a "delete my account" option
