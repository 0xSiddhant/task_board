# Offline-First Task Board

A task board with three columns — To Do, In Progress, Done — built to
stay fully usable without a network connection and sync changes once one
is available.

## Setup

Requires Xcode 26 or newer, iOS 17 or newer.

Open `TaskBoard.xcodeproj`, build, and run. No configuration needed —
the app ships with an in-memory fake backend.

### Optional: Firebase

1. Register an iOS app in the Firebase console using this project's
   bundle identifier.
2. Add `GoogleService-Info.plist` to `TaskBoard/`, the folder holding
   `TaskBoardApp.swift`. The file is gitignored; without it the app
   uses the fake backend.
3. **File → Add Package Dependencies…** →
   `https://github.com/firebase/firebase-ios-sdk`. Add `FirebaseCore`,
   `FirebaseFirestore`, and `FirebaseStorage` to the TaskBoard target.

## Architecture

The app is split into four areas:

- **Features** — one folder per screen (Board, TaskForm, Settings), each
  holding its View and ViewModel together.
- **Services** — grouped by subsystem: `Task`, `Sync` (remote service,
  sync engine), and `Logging` (logger, log upload). `Task` splits again
  into `Model` (domain types and the repository protocol) and
  `Persistence` (the Core Data stack, managed objects, and the repository
  implementation), with `TaskUseCases` sitting above both.
- **Support** — cross-cutting utilities that don't belong to one feature,
  like the network monitor.
- **Components** — UI shared across more than one feature, like the
  status banner.

The task domain follows a light MVVM-plus-use-cases shape: ViewModels
call into a `TaskUseCases` type, which calls a `TaskRepository` protocol.
The concrete implementation is the only place that knows about Core Data.
This isn't full Clean Architecture with a routing layer and per-verb use
case types — for three screens that would have been ceremony, not
architecture. The one boundary that's enforced strictly is that the
domain `Task` model never imports CoreData, which is what keeps the use
case tests running without touching a real database.

## Technical decisions

**Core Data over SwiftData.** I've shipped more with Core Data than
SwiftData, and under a tight deadline that mattered more than SwiftData's
lighter boilerplate. Core Data's background-context story and merge
policies are also better understood at this point, which matters for a
sync engine that's writing from a background actor while the UI reads on
the main thread.

**Outbox pattern for offline writes.** Every create, update, move, or
delete writes to the local database and appends a queue entry in the same
transaction. There's no separate "offline path" — the app always writes
locally first and tries to sync after; being offline just means that
second step waits.

**Fractional-index positions for reordering.** Cards store a `Double`
position instead of an integer index, so reordering one card only needs
to compute a value between its new neighbors rather than rewriting every
row after it.

**Last-write-wins conflict resolution.** Each queued edit captures the
task's `updatedAt` at the moment of the edit. On reconnect, that base
version is compared against the server's current version; if the server
moved on, whichever `updatedAt` is newer wins. I considered field-level
merging but treated it as out of scope given the time available — noted
below as something I'd add.

**Mock remote backend by default.** There's no real backend provided by
the assignment, so a `FakeRemoteTaskService` stands in — configurable
latency, offline, and failure-rate knobs, exposed through a debug
settings screen. This also means the app builds and runs with zero
external configuration, which mattered more to me than wiring up a real
Firebase project the reviewer would need to set up themselves.

**Two-generation log rotation.** The debug logger keeps a `current.log`
and a `previous.log` instead of trimming lines out of one growing file.
When `current.log` hits its size cap, it becomes `previous.log` (dropping
whatever was there before) and a fresh file starts. Total disk usage
stays bounded permanently without a separate cleanup pass.

## Known limitations

- Conflict resolution is last-write-wins at the whole-record level, not
  field-level. Two offline edits to different fields of the same task
  will still have one fully overwrite the other.
- No real backend is wired in by default, so multi-device sync isn't
  demonstrable out of the box — only through the optional Firestore path.
- No pagination or handling for very large task counts; this wasn't a
  stated requirement and the board is expected to hold a modest number of
  cards.
- UI tests weren't written — testing effort went entirely into the
  use-case and sync-engine layer, where the actual logic lives.

