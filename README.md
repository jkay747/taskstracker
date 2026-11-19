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

This repo is already connected to its Supabase project (`twdhmugbmvqpahjaambj`): the URL and publishable key are in `web/config.js` and `apple/Kay2Do/SupabaseConfig.swift`. To point it at a different project, change those two files.

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

### 5. Sign in and bring over the old web list

Sign in once (web or app) with your email. You'll land on "Create my list". To bring over the tasks from the old Claude-hosted "Jason Kay To Dos" page instead, run the one-time import SQL in the SQL Editor, then reload.

## Weekly quote

Each list shows a quote under the weekly theme. By default it's a built-in pick that changes every Monday and is the same for everyone on the list: 52 lines from Rumi, Emerson, Thoreau, Whitman, Gibran, Tagore, Lao Tzu, Marcus Aurelius, Seneca, John Muir and others. Owners and editors can press **Change quote** to step through the picks or type their own, and can turn quotes off under List settings.

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
| `apple/Kay2Do/SettingsView.swift` | Your name, list name, categories, people |
| `.github/workflows/build.yml` | Compiles the Mac and iOS builds when `apple/` changes |
| `.github/workflows/pages.yml` | Publishes `web/` to GitHub Pages when it changes on `main` |

## Not done yet

- Reminders/notifications for due dates, widgets, Siri/Shortcuts
- The app refreshes on a 12-second timer rather than with live updates (the web page is live)
- Works online only; the app doesn't keep an offline copy
- App Store needs: privacy policy, screenshots, a designed icon, and a "delete my account" option
