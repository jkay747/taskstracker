# Kay2-Do

A native task tracker for Mac and iPhone (one SwiftUI app, one codebase), based on the "Jason Kay To Dos" web list.

- Categories (Home, Work, Estate Planning, Long Term to start; rename, recolor, reorder, add up to 12)
- Tasks with due dates, notes, a star for top priority, an owner and other people involved
- A weekly theme line ("This week will be… because…") and a top-three priorities panel
- Search, an owner filter (Everyone / Mine / Unassigned / a person) and a show-completed switch
- iCloud sync between your own devices
- iCloud sharing: share a category with other people, then assign its tasks to them

## How sharing works

You share a **category**, not the whole list. Open a category and use the person button in the toolbar (or "Invite someone to this task…" inside any task). Apple's invitation screen sends a link by Messages, Mail or copy-and-paste. Once someone accepts, they see every task in that category on their own Mac or iPhone, can add tasks, and can check off what's theirs. Categories you haven't shared stay private.

Each person needs an Apple ID signed in to iCloud and a copy of this app. Until the app is on TestFlight or the App Store, that means building it onto their device from Xcode.

Owners are stored by name. Set **Your name** in List Settings on each of your devices so "Mine" works.

## First run in Xcode

Needs Xcode 16 or later and a paid Apple Developer Program membership (iCloud sync and sharing aren't available to free accounts).

1. Open `Kay2Do.xcodeproj`.
2. Select the **Kay2Do** target → **Signing & Capabilities** → choose your **Team**.
3. If the bundle identifier `com.kay2ventures.Kay2Do` is taken or you prefer another, change it, and change the iCloud container to match in three places: the iCloud capability's container list, `Config/Kay2Do.entitlements`, and `Persistence.containerID` in `Kay2Do/Persistence.swift`.
4. Under **iCloud**, make sure **CloudKit** is ticked and the container `iCloud.com.kay2ventures.Kay2Do` is ticked. If it shows in red, press the refresh button or **+** to create it.
5. Pick **My Mac** or your iPhone as the run destination and press Run.

Before a TestFlight or App Store build, open the CloudKit Console for the container and **Deploy Schema Changes** to Production. Development and Production data are separate.

## Layout

| Path | What it is |
| --- | --- |
| `Kay2Do/Model.swift` | Task, category and settings records (Core Data model defined in code) |
| `Kay2Do/Persistence.swift` | Local store, iCloud sync, sharing, moving tasks between categories |
| `Kay2Do/Sharing.swift` | Apple's invitation screens and accepting an invitation |
| `Kay2Do/ContentView.swift` | Sidebar |
| `Kay2Do/TaskListView.swift`, `TaskRow.swift` | The list |
| `Kay2Do/TaskEditor.swift` | Task detail sheet |
| `Kay2Do/SettingsView.swift` | List name, your name, categories |
| `Config/` | Info.plist additions and entitlements |
| `.github/workflows/build.yml` | Compiles the Mac and iOS builds on every push |

## Not done yet

- Reminders/notifications for due dates, widgets, Siri/Shortcuts
- People are matched by name rather than by Apple ID
- No import from the web list (it was empty when this was built)
- App Store needs: privacy policy, screenshots, a designed icon
