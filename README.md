# Kay2-Do

One task tracker, three ways in, one shared list:

| | Where | What it is |
| --- | --- | --- |
| **Web** | `web/` | The planner-sheet list in any browser, published with GitHub Pages |
| **Mac + iPhone** | `apple/` | A native SwiftUI app (one codebase for both) |
| **Data** | `supabase/` | The shared database both of them use |

A task you add on your iPhone shows up on the web page within seconds, and the other way round. Everyone signs in with their email (a 6-digit code, no password), and you share a list by inviting someone's email address.

Features, everywhere:

- Categories (rename, recolor, reorder, add up to 12)
- Tasks with due dates, notes, a star for top priority, an owner and other people on the task
- A weekly theme line ("This week will be… because…") and a top-three priorities panel
- Search, an owner filter (Everyone / Mine / Unassigned / a person) and a show-completed switch
- Several lists per account, each shared with its own people
- Roles: **owner** (everything, including who's on the list), **editor** (anything but people), **contributor** (adds tasks; checks off and edits the ones they own, are on, or created)

## Set up (once, about 15 minutes)

### 1. Make the Supabase project

1. Create a free account at [supabase.com](https://supabase.com) and a **New project**. Note the database password somewhere safe; the apps don't need it.
2. Open **SQL Editor → New query**, paste all of [`supabase/schema.sql`](supabase/schema.sql), and press **Run**. It's safe to run again later.
3. Open **Authentication → Emails** (Email Templates). In both **Confirm signup** and **Magic Link**, add the code to the message, for example:

   ```html
   <h2>Your Kay2-Do code</h2>
   <p>Enter this code to sign in: <strong>{{ .Token }}</strong></p>
   <p>Or follow this link on this device: <a href="{{ .ConfirmationURL }}">sign in</a></p>
   ```

   The Mac and iPhone app needs the code. The web page accepts either the code or the link.
4. Open **Project Settings → API** and copy the **Project URL** and the **anon public** key.

Supabase's built-in email sender is limited to a few emails an hour, which is fine for a few people. For more, add your own SMTP sender under **Authentication → SMTP Settings**.

### 2. Point both apps at it

Put the two values in both places (the anon key is meant to be public; row-level security in the schema is what keeps lists private):

- `web/config.js` → `supabaseUrl` and `supabaseAnonKey`
- `apple/Kay2Do/SupabaseConfig.swift` → `url` and `anonKey`

If you leave them blank, each app asks for them the first time it opens and remembers them on that device.

### 3. Publish the web page

1. On GitHub: **Settings → Pages → Build and deployment → Source: GitHub Actions**.
2. Push to `main`. The **Web app** workflow publishes `web/` to `https://<your-user>.github.io/taskstracker/`.
3. Back in Supabase, **Authentication → URL Configuration**: set **Site URL** to that address so sign-in links come back to the page.

To try it locally instead, run `python3 -m http.server -d web 8000` and open <http://localhost:8000> (add that URL to Supabase's redirect URLs too).

### 4. Build the Mac and iPhone app

Needs Xcode 16 or later. A free Apple account is enough to run it on your own Mac or iPhone; TestFlight and the App Store need the paid Developer Program.

1. Open `apple/Kay2Do.xcodeproj`.
2. Select the **Kay2Do** target → **Signing & Capabilities** → choose your **Team**. Change the bundle identifier if Xcode says it's taken.
3. Pick **My Mac** or your iPhone and press **Run**.

### 5. Sign in and bring over the old web list

Sign in once (web or app) with your email. You'll land on "Create my list". To bring over the tasks from the old Claude-hosted "Jason Kay To Dos" page instead, run the one-time import SQL in the SQL Editor, then reload.

## Sharing a list

1. **List settings → People**: type their email, pick **Contributor** or **Editor**, and press **Invite**.
2. Use **Copy invite message** (web) or **Send Invite Message** (app) and send it to them. Supabase doesn't send an email by itself at this point.
3. They open the web page or the app and sign in with that email. The list is there, and any task you assigned to their email address is now linked to them.

You can assign a task to a typed name or email before someone has joined. It shows as "not linked" until they do.

## Layout

| Path | What it is |
| --- | --- |
| `supabase/schema.sql` | Tables, row-level security, and the functions both apps call (`create_list`, `invite_member`, `accept_invites`, `list_people`) |
| `web/index.html` | The whole web app (HTML, CSS, JS); uses supabase-js from a CDN and live updates |
| `web/config.js` | Supabase URL and anon key for the web app |
| `apple/Kay2Do/Backend.swift` | Small Supabase client: email-code sign-in, token refresh, REST calls |
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
