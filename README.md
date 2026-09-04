# ZenSched Crop-Scout Reference Kit

A copy-pasteable setup for a 1–5 person crop-scout / independent-agronomy shop (field walks, disease calls, tissue and soil samples, stand counts) that wants an AI assistant to run field scheduling, GPS-verified Scout Records at a field-corner pin, a local pest-count extract, and invoicing. ZenSched handles the live schedule, the scout's phone app, GPS check-ins at the field corner, and the growth-stage / pest-count / canopy-photo Scout Record. A small local database on your computer holds your growers, fields, prices, cadence, visit summaries, and invoices.

**You do not need to know how to program or write SQL to use this.** You type plain English to your AI assistant ("schedule this week", "add Rivera's North 80", "what was the aphid count", "who owes me money?") and the AI does the work using two tools you set up once. Setup takes about 15 minutes and is the only technical part.

If you *are* a developer, skip to [For developers](#for-developers).

## What this kit is not — read this first

**What it is:** GPS-verified proof that a scout was at the field corner, a Scout Record (growth stage, pest count, pest type, up to 2 canopy photos), a local extract of those records for your own files, and invoices built from completed walks.

**What it is not:**

- **Not a CCA / PCA written recommendation, not a receituário, and not an official agronomic prescription.** `scout_log` is *your* copy of what the scout typed on the phone (date, field, stage, pest, count). It is not a recommendation, not a threshold decision, not a Brazilian **receituário agronômico** (Lei 14.785/2023 / Confea Resolução 1.149/2025), and not a prescription a grower can spray from. If they need a written rec, you still write it on your own letterhead / CREA form.
- **Not a pesticide-use log and not a NAPIS filing.** This kit does not produce a FIFRA, state applicator, or farm spray record, and it is not a NAPIS / official pest-survey submission. Counts on the Scout Record are observations, not products applied and not a regulatory report.
- **Not NDVI, yield, or satellite.** There is no imagery pipeline, no stand-count AI, and no yield model. A stand-count visit is the same Scout Record with `pest_type` = None and a count in `pest_count` if you want to reuse the number field that way — or just notes after the fact.
- **Not a signed legal document.** The Scout Record has no signature field. On ZenSched a signature field replaces the Submit button, so adding one would make every walk look like the scout had signed something. Submitting the form is just submitting the form.

If any of those is a deal-breaker, this kit is not for you. If you want weekly field cadence, a GPS corner pin, and a local extract you can file next to your real recommendations, read on.

## What lives where

**ZenSched (source of truth for what happened, when, and where):**

- Locations (one per field, pinned at a GPS corner; the check-in radius is a **policy** setting)
- Workers (scouts with the mobile app)
- Events (one "Scout" job per field, renewed every 60 days)
- Shifts (each scheduled walk, with push notifications to the scout)
- GPS punches (check-in/check-out with distance-from-the-pin verification)
- The Scout Record form (growth stage, pest count, pest type, up to 2 canopy photos) and every submission
- Timesheets (verified hours worked)

**Local SQLite database (`crop-scout.db`, on your computer):**

- Grower contact and billing notes
- Fields: name, crop, acres, county, GPS corner, cadence (weekly / biweekly / monthly / seasonal / on-demand), per-visit rate, next walk date, access notes (gate, muddy approach, dog) that **never leave your computer**
- Your price list (field scout, disease scout, tissue sample, soil sample, stand count)
- Scouts, including CCA / PCA license numbers that **never leave your computer**
- Completed visits with a summary of each Scout Record, the scout-log extract, and invoices
- Your settings (timezone, default scout, invoice prefix, Scout Record form id)

**Never duplicated:** the live schedule, punches, timesheets, and canopy photos stay in ZenSched. The local database only stores *references* to them plus a short per-visit summary so you can answer "what was the aphid count on North 80" without paying to re-read reports.

### Privacy note

Gate codes, muddy-approach notes, "park at the south corner," CCA / PCA license numbers, and **grower / farm / person names** are stored only in the local database. `SKILL.md` forbids the AI from putting them into any ZenSched field. Give approach notes to your scout yourself, by whatever channel you trust. ZenSched only ever sees the field label (`{field code} - {road}`, never the grower) and the GPS corner.

## How it works day to day

Your AI assistant has two sets of tools:

1. **ZenSched tools** (`location_create`, `shift_create`, `form_submissions`, `shift_list`, ...) that talk to ZenSched over the internet.
2. **A SQLite tool** (`sqlite_query`, `sqlite_execute`) that reads and writes `crop-scout.db` on your computer.

When you say "schedule this week," the AI reads which fields are due from the local database (`next_service_date` in the next 7 days), creates one shift per walk on ZenSched, and tells you what it did. Your scout sees the walks in the app, checks in at the field corner (GPS-verified), walks, fills in the Scout Record with canopy photos, and checks out. Later you say "record this week's visits" and the AI pulls the completed shifts and records, saves a summary locally, and advances each field's next date (weekly +7, seasonal +90 days, on-demand clears it). "Scout log for last week" is a local query. You never run SQL yourself. `SKILL.md` in this repo is the instruction sheet that teaches the AI how to do all of this; you paste it into your AI tool once.

A typical visit costs about **$0.35** on ZenSched: GPS in $0.10 + GPS out $0.10 + reading a Scout Record that has canopy photos $0.15. Pinning a new field (client lat/lng) is $0.03 once. The AI states the cost before it spends.

## Setup

### 0. What you need

- **An AI tool that supports MCP.** These instructions use Claude Desktop (Windows or Mac). Cursor works too.
- **Node.js 20 or newer.** The SQLite tool runs on it. Download the LTS installer from [nodejs.org](https://nodejs.org/) and run it with the defaults. This is the only software install.
- You do **not** need the `sqlite3` command-line program, Python, or Git.

### 1. Make a folder for your data

Create a folder where the database will live and write down its full path. Examples:

- Windows: `C:\Users\YourName\crop-scout`
- Mac: `/Users/yourname/crop-scout`

The database file will be created automatically inside this folder the first time the AI uses it.

### 2. Add both tools to your AI's config file

Open the MCP configuration file for your AI tool:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json` (paste that into the File Explorer address bar)
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json` (in Claude Desktop: Settings → Developer → Edit Config)
- **Cursor:** Settings → MCP → Add new global MCP server

Paste in the contents of `mcp.json.example` from this repo, then change one line, the `SQLITE_PATH`, to point at your folder from step 1 plus `\crop-scout.db` (Windows) or `/crop-scout.db` (Mac):

```json
{
  "mcpServers": {
    "zensched": {
      "url": "https://mcp.zensched.com/mcp",
      "headers": { "Authorization": "Bearer zsc_your_key_here" }
    },
    "crop-scout-db": {
      "command": "npx",
      "args": ["-y", "easy-sqlite-mcp"],
      "env": { "SQLITE_PATH": "/Users/yourname/crop-scout/crop-scout.db" }
    }
  }
}
```

**Windows path gotcha:** inside a JSON file every backslash must be doubled. Write `"C:\\Users\\YourName\\crop-scout\\crop-scout.db"`, not `"C:\Users\..."`. A single backslash will silently break the config.

**Leave `zsc_your_key_here` exactly as it is for now.** You do not have a key yet. The ZenSched tools that create your account work without one, and you will fill this in during step 3.

Save the file and **fully quit and reopen** your AI tool (on Mac, Cmd-Q; on Windows, right-click the tray icon → Quit). It only reads this file on startup.

### 3. Create your ZenSched account

In a new chat, type:

> Call `zensched_guide`, then call `account_create` with org_name "My Crop Scout" (use my real business name if I told you one). Show me the `zsc_` key it returns.

Copy the `zsc_` key. Go back to the config file from step 2, replace `zsc_your_key_here` with your real key, save, and fully quit and reopen the AI tool again.

Some clients can adopt the key mid-session with `account_use_key`; you can ask the AI to try that to keep going immediately, but still update the config file so the key survives restarts. Keep the key private; it is the password to your account.

### 4. Create the database tables

Open `schema.sql` from this repo in any text editor, copy the whole thing, and paste it into the chat with this message in front of it:

> Create these tables in my crop-scout database. Run each statement one at a time using the SQLite tool, then list the tables to confirm.

The AI will run the statements one at a time and confirm the tables exist. The `crop-scout.db` file now exists in your folder, pre-loaded with a starter price list you can change.

If you happen to have the `sqlite3` command-line tool, `sqlite3 crop-scout.db < schema.sql` does the same thing, but it is not required.

### 5. Teach the AI the workflow

Paste the contents of `SKILL.md` into your AI tool as standing instructions. In Claude Desktop, create a Project and put it in the project instructions; in Cursor, save it as a rule. Then tell it your basics once:

> My business is Prairie Scout in Ames, Iowa (Central time). Save that in settings, and set up the Scout Record form.

It writes those to the `settings` table, creates the Scout Record form on ZenSched (free), and saves the form id so every walk gets it automatically.

**Check-in radius.** The default pin uses `checkin_radius_m=200` on `location_create`, but ZenSched **enforces** the radius through the account's policy, not per field. With geofencing on it raises anything under 100 m to about 91 m (300 ft) — too tight for a field corner if the scout walks in. Ask the AI to "set the check-in radius to 300 m" (`policy_update`) or to move the pin onto the right corner (`location_update`, free). Do not ask it to widen the radius "on that field" — that field is informational only.

### 6. Funding (only when asked)

The first 200 ZenSched tool calls per day are free. Some things are metered: creating a location (geocode or client lat/lng, $0.03), inviting a scout ($0.25), each GPS-verified check-in or check-out ($0.10), and reading a Scout Record ($0.05, or $0.15 when it has photos). When a metered call happens without funds, the AI will get a `payment_required` response and tell you how to add the $5 activation deposit, which is credited to your balance. You will not be charged without seeing this first.

A typical visit is about $0.35 (in + out + photo record). A scout doing 8 fields a day is about $2.80 in meters that day, plus $0.03 the first time you add each field. The AI states the cost before it spends.

## Using it

Everything after setup is plain English. Examples:

- "Add Tom Rivera, Rivera Farms, tom@example.com, 515-555-0144. North 80, corn, 80 acres, Story County. GPS corner 42.0308, -93.6319. Weekly field scout $125 starting Monday 7am. South approach, muddy after rain."
- "Add a one-off disease scout for Maya Chen, Chen Family Farm, South 40 soybeans, 40 acres, Tuesday 9, $180. Corner 42.0180, -93.6100."
- "Invite Priya Shah, priya@example.com, and make her the default scout."
- "Set the check-in radius to 300 m."
- "Schedule this week for Priya."
- "Record this week's visits."
- "Scout log for last week."
- "Draft invoices for everyone with uninvoiced work."
- "Who still owes me money?"
- "Rivera paid INV-2026-0001."
- "Pause the Rivera account until November."
- "Add a seasonal tissue sample on the Bottom 40."

See `QUICKSTART.md` for the first-week walkthrough and `example-workflow.md` for exactly which tools the AI calls behind each of these.

### What "invoice" means here

"Draft an invoice" records the invoice in your database (number, date, due date, amount, which visits) and the AI writes out a plain-text invoice you can paste into an email or text message, with a line per walk and a note that the visit was GPS-verified. It does **not** generate a PDF, email it for you, or collect payment. Invoices do not list pest counts or license numbers unless you ask. When the grower pays, tell the AI ("Rivera paid INV-2026-0001") and it marks it paid. If you outgrow this, the invoice records are simple enough to import into any accounting tool.

## Mobile app for scouts

- **Android:** [Google Play](https://play.google.com/store/apps/details?id=com.zensched.app)
- **iOS:** [TestFlight](https://testflight.apple.com/join/Wp51m5Yq)

When you invite a scout, they get an email, install the app, and can immediately see their walks, check in and out with GPS verification at the field corner, and fill in the Scout Record with canopy photos. The record is attached to each walk automatically. There is no signature step — they tap Submit.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| AI says it has no ZenSched tools | Config file not saved, or the app was not fully restarted | Check the JSON is valid (paste it into [jsonlint.com](https://jsonlint.com)), then quit and reopen the app |
| AI says it has no SQLite / `crop-scout-db` tools | Node.js not installed, or bad `SQLITE_PATH` | Install Node.js LTS; on Windows check every backslash is doubled |
| `SQLITE_PATH` points nowhere / "unable to open database" | Folder from step 1 does not exist | Create the folder; the file is created automatically but the folder is not |
| ZenSched tools return an auth error | Key still says `zsc_your_key_here`, or was pasted with a space | Re-paste the key, restart |
| `payment_required` | Metered call with no balance | Follow the instructions in the response; $5 deposit |
| AI creates shifts at the wrong hour | Timezone not set, or daylight saving changed and `timezone_offset` was not updated | "Set my timezone offset to -05:00 in settings" (use your own offset). US/AU clocks move; Brazil and India do not. After the first Sunday of November, Ames Central is `-06:00`. |
| Shift creation fails for dates a couple of months out | The field's 60-day ZenSched event has expired | Say "renew the events"; the AI runs the roll-over in `SKILL.md` and retries |
| Scout's check-in not GPS-verified at the field | Pin is the wrong corner, or the default ~300 ft circle is too small | Ask the AI to widen `checkin_radius_m` with `policy_update` (not on the field), or run `location_update` to the right corner (free) |
| Pin landed on the county road / farm mailbox | `location_create` was given a street address, which ignores lat/lng | Recreate or `location_update` with the GPS corner only; leave `street_address` empty |
| Scout does not see the Scout Record | Form not assigned to that field's event | "Attach the Scout Record to North 80's event" (`form_assign`) |
| "Scout log" comes back empty | Visits not recorded yet | "Record this week's visits" first |
| AI asks you to run SQL yourself | It does not have `SKILL.md` loaded | Re-paste `SKILL.md` as project instructions |
| AI refuses to put a gate code in ZenSched | Working as intended | Give it to the scout directly |
| AI offers a spray rec or a state chemical form | It shouldn't | This kit does not produce those; use your own letterhead / state form |

If something is confusing or broken in ZenSched itself, ask the AI to call `feedback_submit` with a description. It is free, needs no account, and a human reads every submission.

## For developers

**Architecture.** Two MCP servers, no application code. The agent is the integration layer; `SKILL.md` is the spec it follows. ZenSched is authoritative for operations (schedule, punches, forms); SQLite is authoritative for CRM, per-field cadence, visit summaries, the scout-log extract, and billing; each side stores only the other's **integer** IDs, plus a per-visit report summary cached locally because submission reads are metered.

**Data model decisions.**

- One ZenSched **location** per field, permanent, stored on `fields.zensched_location_id` as an integer. Created with `location_create(name, lat=..., lng=..., checkin_radius_m=200, idempotency_key=...)` and **no** `street_address` so `pin_quality` is `client` (the GPS corner). Passing a farm 911 / road string geocodes the road and **ignores** lat/lng. `name` is limited to 50 characters; `field_label` is `{field code} - {road}` (e.g. `North 80` or `South 40 - County road 15`), **never the grower or farm name**. `checkin_radius_m` on `location_create` is informational; the enforced radius is `policy_update(0, '{"checkin_radius_m": N}')`, and with geofencing on the platform raises values under 100 m to 300 ft — too tight for a field. Kits must say "widen the radius with policy_update", never "on that field".
- **Events are capped at 60 days by ZenSched**, so an event cannot be a permanent season template. Each field holds its *current* event in `fields.zensched_event_id` and its last covered date in `fields.event_valid_until`. The agent creates a new event (`event_create(location_id, title="Scout - <field_name>", start_date, end_date=start+59 days, idempotency_key="event-field-{field_id}-{YYYYMMDD}")`) whenever a shift date is later than `event_valid_until`, calls `form_assign(form_id, event_id=...)` on it, and updates the row. `fields_due` exposes `event_needs_roll` per row and `events_expiring` lists fields due for renewal within 14 days. Shifts already created on the old event remain valid. When recording a completed visit whose `event_id` no longer matches a field, the agent falls back to `event_get(event_id).location_id` against `fields.zensched_location_id`.
- **Cadence is per field, not per grower.** A farm often has a weekly corn field and an on-demand soy field. `fields.service_frequency` is `weekly | biweekly | monthly | seasonal | on-demand`. `fields_due` is every active field with `next_service_date <= today+7` joined to its active grower, emitting `start_iso` / `end_iso` (preferred start or `settings.default_shift_start`, duration from the service or `default_shift_minutes`) and the shift `idempotency_key`. Two fields on the same grower produce two rows.
- **The `advance_service_date_on_visit` trigger** sets `last_service_date` and `next_service_date` on every visit insert: +7 / +14 / +1 month / **+90 days** / NULL. Seasonal is +90 days, not `+3 months`, so the interval does not drift with month length. That +90 is the *local* next-walk date only — the ZenSched event is still ≤60 days and must roll (`event_needs_roll`) before a shift 90 days out. Never create one 90-day event. Recording a one-off on a recurring field also moves the cadence; `SKILL.md` tells the agent to set the date back if the owner says so.
- Rate lives on the **field** (`service_rate`) so a shop can charge off-list per field. `fields.service_id` is the default; `visits.service_id` is what was actually done (a weekly field-scout field can still get a `disease_scout` visit).
- `visits.zensched_shift_id` and `scouts.zensched_worker_id` are integer `UNIQUE`. `visits.report_dc_id` holds the form `submission_id`. `growth_stage` and `pest_type` are `CHECK`-constrained to the form's option labels. `pest_count` is the number as typed.
- `fill_visit_scout` sets `scout_id` from `zensched_worker_id` when the agent leaves it NULL.
- `invoices.invoice_number` is auto-assigned by trigger as `{prefix}-{YYYY}-{0001}`.
- **`scout_log`** is a view over recorded visits (keeps `pest_type` = None — a zero-pressure walk is still a billed scout). One row per visit. It does not transmit anything and is not a recommendation.
- `fields.access_notes` and `scouts.license_no` are the columns that must never be sent to ZenSched; `SKILL.md` rule 6 enforces it. `fields_due` still *selects* `access_notes` so the agent can tell the owner to pass them to the scout.
- `PRAGMA foreign_keys = ON` is in `schema.sql` and `SKILL.md` tells the agent to run it per session; SQLite does not persist it.

**Scout Record form.** Created once with `form_create(title, fields_json, idempotency_key="form-scout-record")`; the exact `fields_json` is in `SKILL.md` and `example-workflow.md` (byte-identical) and was validated against ZenSched's `_validate_fields`. Every field carries an explicit `identifier` so submission `data` keys are stable (`growth_stage`, `pest_count`, `pest_type`, `canopy`; section `sec_scout`). Option keys are derived by ZenSched from the labels (lowercase, non-alphanumerics → `_`, truncated at 30 characters); every option here is well under 30 characters, so nothing truncates. **No `signature` field** — the phone keeps a Submit button, and submitting is not a legal attestation. Disease / tissue / stand-count walks reuse this form. Attaching is `form_assign(form_id, event_id=...)`.

**Idempotency keys.** Deterministic, derived from local IDs:

- location: `loc-field-{field_id}`
- event: `event-field-{field_id}-{YYYYMMDD window start}`
- shift: `shift-field-{field_id}-{YYYYMMDD}` for the first walk that day; a same-day second walk, a scout swap, or any replacement after `shift_cancel` appends `-2`, `-3`, … so a cancelled key is never reused (ZenSched replays the cached response for 24 hours)
- worker: `worker-{email}`
- form: `form-scout-record`; assignment: `assign-scout-record-{event_id}`

ZenSched caches idempotent responses for 24 hours.

**Timestamps.** `shift_create` takes `start` and `end` in ISO 8601 with an explicit offset. Always use the business's local offset from `settings.timezone_offset` (e.g. `2026-09-07T07:00:00-05:00`), never `Z`. The view builds these strings so the agent does not have to. The offset is a fixed setting, not a zone name, so it must be updated when daylight-saving time starts or ends (`SKILL.md` rule 8; `example-workflow.md` shows the November flip to `-06:00` for Ames). Brazil and India have no DST.

**Metered reads.** `form_submissions` and `form_export` bill $0.05 per submission read ($0.15 with media); `form_export` is preferred for a week at a time. The kit stores the summary and media URLs on `visits` on first read so later scout-log questions are answered from SQLite. `shift_list`, `shift_status`, `event_get`, and `timesheet_export(mode="hours"|"raw")` are free.

**SQLite MCP server.** `mcp.json.example` uses [`easy-sqlite-mcp`](https://github.com/chenkumi/easy-sqlite-mcp) (Node, `better-sqlite3`, `SQLITE_PATH` env var). Its `sqlite_execute` calls `prepare()`, so it accepts **one statement per call**; `schema.sql` is written so every statement stands alone and is idempotent. Any SQLite MCP server with read and write tools will work; adjust the tool names in `SKILL.md`.

**Schema test.** The schema was verified by splitting the file into its 45 statements with `sqlite3.complete_statement` and executing each individually (as the MCP server does) twice for idempotency (seed rows not duplicated), then exercising: all 7 tables, 5 views, and 6 triggers present; every view on an empty database; the `advance_service_date_on_visit` trigger for weekly (+7), biweekly (+14), monthly (+1 month), **seasonal (+90 days, 2026-09-07 → 2026-12-06, not +3 months / Dec 7)**, and on-demand (NULL); `fill_visit_scout` from `zensched_worker_id`; `UNIQUE` on `zensched_shift_id`; every `CHECK` (frequency, `preferred_start`, growth_stage, pest_type); `fields_due` `start_iso` / `end_iso` / `idempotency_key` / worker / minutes / GPS corner; `event_needs_roll` flipping exactly when `event_valid_until < next_service_date`; inactive field, inactive grower, and +20-day rows excluded; two fields on one grower → two due rows; `events_expiring`; `scout_log` keeping zero-pressure `None`; invoice numbering (auto `INV-2026-0001`, explicit number kept); `visits_to_invoice` / `invoices_outstanding` filters; cascade delete and scout set-null; `updated_at`; integer types on ZenSched ID columns. Form payload validated against `_validate_fields` (5 fields, no signature, SKILL.md byte-identical to example-workflow.md, every option key ≤ 30 characters). 98 checks, all passing.

## Support

- ZenSched docs: <https://www.zensched.com/docs/>
- Tool reference: <https://www.zensched.com/docs/tools/>
- Feedback: ask your AI to call `feedback_submit` (categories: `bug`, `friction`, `missing_capability`, `docs`, `billing`, `feature`, `other`)

## License

MIT. See `LICENSE`.
