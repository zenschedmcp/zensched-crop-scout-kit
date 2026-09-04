# Quickstart

Setup is about 15 minutes, once. After that everything is plain English to your AI. Each step below tells you what to do and, where relevant, exactly what to type to the AI.

You need: Claude Desktop (or Cursor) and [Node.js LTS](https://nodejs.org/) installed. Nothing else.

Before you start, read the "What this kit is not" section of `README.md`. Short version: this is GPS-verified field-corner proof plus a local extract of the Scout Record. It is **not** a CCA recommendation and **not** a spray log.

## 1. Make a data folder

Create a folder such as `C:\Users\YourName\crop-scout` (Windows) or `/Users/yourname/crop-scout` (Mac). Note the full path.

## 2. Add the two tools to your AI's config

Open the config file:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Cursor:** Settings → MCP → Add new global MCP server

Paste this in and fix only the `SQLITE_PATH` line to match your folder from step 1:

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

- On Windows, double every backslash: `"C:\\Users\\YourName\\crop-scout\\crop-scout.db"`.
- Leave `zsc_your_key_here` as it is. You get the real key in the next step.

Save, then **fully quit and reopen** the AI app.

## 3. Create your ZenSched account

Type to the AI:

> Call zensched_guide, then account_create with org_name "Prairie Scout". Show me the zsc_ key.

Copy the key into the config file in place of `zsc_your_key_here`. Save. Quit and reopen the app once more. (You can also ask the AI to call `account_use_key` with the key to continue right away, but update the file anyway so it sticks.)

## 4. Create the database tables

Copy the full contents of `schema.sql` and paste it into the chat with this line above it:

> Create these tables in my crop-scout database. Run each statement one at a time with the SQLite tool, then list the tables to confirm.

## 5. Give the AI its instructions

Paste `SKILL.md` into the AI as standing instructions (Claude Desktop: a Project's instructions; Cursor: a rule). Then:

> My business is Prairie Scout in Ames, Iowa, Central time. Save that to settings and create the Scout Record form.

The AI saves your settings and calls `form_create` once (free) to build the Scout Record your scouts fill in: growth stage, pest count, pest type, up to 2 canopy photos. No signature. It stores the form id so every walk gets it.

## 6. Add your first two fields

> Add Tom Rivera, Rivera Farms, tom@example.com, 515-555-0144. Field North 80, corn, 80 acres, Story County. GPS corner 42.0308, -93.6319. Weekly field scout $125 starting Monday 2026-09-07 at 7. South approach, muddy after rain.

> Add a one-off disease scout for Maya Chen, Chen Family Farm, maya@example.com, 515-555-0190. South 40 soybeans, 40 acres, Tuesday 2026-09-08 at 9, $180. Corner 42.0180, -93.6100. County road 15, no gate.

Behind the scenes the AI inserts each grower and field, calls `location_create` with the GPS corner (lat/lng, no street address, $0.03, may trigger the $5 activation deposit the first time), creates a 60-day `event_create` for the field, attaches the Scout Record with `form_assign`, and saves the IDs. Approach notes go only into the local database. You just see a confirmation.

## 7. Invite your scout and widen the radius

> Invite Priya Shah at priya@example.com as a scout and make her my default. Set the check-in radius to 300 m.

Priya gets an email ($0.25), installs the app ([Android](https://play.google.com/store/apps/details?id=com.zensched.app) / [iOS TestFlight](https://testflight.apple.com/join/Wp51m5Yq)), and activates. The radius is set with `policy_update`, not on either field. Give her the south-approach note yourself; the AI will not put it in ZenSched.

## 8. Schedule the week

> Schedule this week for Priya.

The AI reads `fields_due`, creates one shift per walk on ZenSched, and summarizes by day. Priya gets a push notification for each, with the Scout Record attached. It will confirm each visit is about $0.35 once she punches and you read the canopy photos.

## 9. After the work is done

> Record this week's visits, show me the scout log, then draft invoices for anyone with uninvoiced work.

The AI pulls the completed, GPS-verified shifts and the Scout Records from ZenSched (reading records is metered, so it tells you the cost first), saves a per-visit summary, advances Rivera North 80 by a week and clears Chen's on-demand date, shows the scout-log extract (your copy, not a recommendation), creates invoice records, and writes out each invoice as text you can paste into an email.

> Tom paid INV-2026-0001.

Marks it paid.

## What next

- `README.md` for the full explanation, the recommendation / spray-log boundary, troubleshooting table, and developer notes
- `example-workflow.md` to see the exact tool calls behind each step above
