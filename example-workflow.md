# Example Workflow: What the AI Does Behind Each Request

This shows the exact tool calls the agent makes for a first week of operation, following `SKILL.md`. The owner only types the quoted lines; everything else is the agent's work. Assumes setup from `QUICKSTART.md` is complete (both MCP servers configured, `schema.sql` loaded, `SKILL.md` given as instructions).

IDs and responses are illustrative. ZenSched IDs are integers.

Shop: **Prairie Scout**, Ames, Iowa, Central time (`-05:00` in September). Two fields (weekly corn walk + one-off soy disease scout), one scout, then invoice.

Access notes (muddy south approach) and any CCA / PCA license number stay in SQLite. They are never sent to ZenSched. The GPS corner **is** sent — that is the pin.

## Session start (every session)

```
sqlite_execute: PRAGMA foreign_keys = ON;
sqlite_query:   SELECT key, value FROM settings;
  → business_name = My Crop Scout, timezone_offset = -05:00,
    default_worker_id = NULL, default_shift_start = 07:00,
    default_shift_minutes = 45, invoice_due_days = 14, invoice_prefix = INV,
    scout_record_form_id = NULL, event_window_days = 60,
    default_checkin_radius_m = 200
```

## "My business is Prairie Scout in Ames, Iowa, Central time."

```
sqlite_execute: UPDATE settings SET value = 'Prairie Scout' WHERE key = 'business_name';
sqlite_execute: UPDATE settings SET value = '-05:00' WHERE key = 'timezone_offset';
```

> Saved. I'll schedule everything in Central time (-05:00). You don't have a Scout Record form yet; it's free to create and every walk will come back with growth stage, pest count, pest type, and up to 2 canopy photos. No signature — this is an internal scout record, not a CCA recommendation, not a receituário or official agronomic prescription, not a NAPIS report, and not a spray log. Want me to set it up now?

Owner: *"yes"*

```
form_create:
  title: "Scout Record"
  idempotency_key: "form-scout-record"
  fields_json: (the JSON below, passed as one string)
```

```json
[
  {"type": "section", "label": "Scout record", "identifier": "sec_scout",
   "text": "Walk the field from the GPS corner. Count pests the way this grower asked (per plant, per 20 plants, or per sweep). Two canopy photos help. This is an internal scout record, not a CCA recommendation, not a receituário or official agronomic prescription, not a NAPIS report, and not a spray log."},
  {"type": "select", "label": "Growth stage", "identifier": "growth_stage", "required": true,
   "options": ["Emergence", "Vegetative", "Flowering", "Grain fill", "Mature", "Post-harvest"]},
  {"type": "number", "label": "Pest count", "identifier": "pest_count", "required": true},
  {"type": "select", "label": "Pest type", "identifier": "pest_type", "required": true,
   "options": ["None", "Aphids", "Armyworm", "Corn rootworm", "Spider mites", "Whitefly", "Weeds", "Disease", "Other"]},
  {"type": "photo", "label": "Canopy photos", "identifier": "canopy", "max_images": 2}
]
```

```
  → form_id: 501, fields: [ ...5 fields echoed with identifiers... ]

sqlite_execute: UPDATE settings SET value = '501' WHERE key = 'scout_record_form_id';
```

> Scout Record form created. I'll attach it to every field automatically. Disease walks, tissue pulls, and stand counts use this same form. There is no signature step.

## "Add Tom Rivera, Rivera Farms, tom@example.com, 515-555-0144. Field North 80, corn, 80 acres, Story County. GPS corner 42.0308, -93.6319. Weekly field scout $125 starting Monday 2026-09-07 at 7. South approach, muddy after rain."

```
sqlite_query:   SELECT service_id, price, default_minutes FROM services WHERE code = 'field_scout';
  → 1, 125.00, 45

sqlite_execute:
  INSERT INTO growers (grower_name, farm_name, contact_email, contact_phone)
  VALUES ('Tom Rivera', 'Rivera Farms', 'tom@example.com', '515-555-0144');
  → lastInsertRowid = 1

sqlite_execute:
  INSERT INTO fields (grower_id, field_name, field_label, crop, acres, county,
                      corner_lat, corner_lng, access_notes, service_id, service_rate,
                      service_frequency, next_service_date, preferred_start)
  VALUES (1, 'North 80', 'North 80', 'corn', 80, 'Story',
          42.0308, -93.6319, 'South approach. Muddy after rain — park on the gravel, not the rows.',
          1, 125.00, 'weekly', '2026-09-07', '07:00');
  → lastInsertRowid = 1
```

Agent (first metered call this session, rule 11):

> Creating North 80 on ZenSched costs $0.03 to pin the GPS corner. If your account isn't funded yet you'll get a prompt for the $5 activation deposit. Go ahead?

Owner: *"yes"*

```
location_create:
  name: "North 80"
  lat: 42.0308
  lng: -93.6319
  checkin_radius_m: 200
  idempotency_key: "loc-field-1"
  → location_id: 9201, lat: 42.0308, lng: -93.6319, pin_quality: "client"
    billing: { meter: "geocode", units: 1, price: 0.03 }
```

`street_address` is **empty** so the pin stays on the corner. The south-approach note is **not** in `notes`. It lives only in `fields.access_notes`. `checkin_radius_m` on the location is informational; the enforced radius is the policy (see later).

```
event_create:
  location_id: 9201
  title: "Scout - North 80"
  start_date: "2026-09-07"
  end_date:   "2026-11-05"          ← start + 59 days (60-day cap)
  idempotency_key: "event-field-1-20260907"
  → event_id: 7201

form_assign:
  form_id: 501
  event_id: 7201
  idempotency_key: "assign-scout-record-7201"
  → status: "assigned", form_id: 501, event_id: 7201, policy_id: 0

sqlite_execute:
  UPDATE fields SET zensched_location_id = 9201, zensched_event_id = 7201, event_valid_until = '2026-11-05'
  WHERE field_id = 1;
```

> Added Rivera Farms, North 80 (corn, 80 ac). Weekly field scout at $125, next walk Monday Sep 7 at 7:00. The south-approach note is saved on your computer only; give it to Priya directly. The pin is the SW corner. The ZenSched event runs through Nov 5; I'll renew it automatically when scheduling gets that far.

## "Add a one-off disease scout for Maya Chen, Chen Family Farm, maya@example.com, 515-555-0190. South 40 soybeans, 40 acres, Tuesday 2026-09-08 at 9, $180. Corner 42.0180, -93.6100. County road 15, no gate."

Same pattern. The agent does not re-ask about the $0.03 (owner already approved pinning this session). Frequency is `on-demand`.

```
sqlite_query:   SELECT service_id, default_minutes FROM services WHERE code = 'disease_scout';
  → 2, 60

sqlite_execute:
  INSERT INTO growers (grower_name, farm_name, contact_email, contact_phone)
  VALUES ('Maya Chen', 'Chen Family Farm', 'maya@example.com', '515-555-0190');
  → lastInsertRowid = 2

sqlite_execute:
  INSERT INTO fields (grower_id, field_name, field_label, crop, acres, nearest_road,
                      corner_lat, corner_lng, access_notes, service_id, service_rate,
                      service_frequency, next_service_date, preferred_start)
  VALUES (2, 'South 40', 'South 40 - County road 15', 'soy', 40, 'County road 15',
          42.0180, -93.6100, 'No gate. Enter from CR 15.',
          2, 180.00, 'on-demand', '2026-09-08', '09:00');
  → lastInsertRowid = 2

location_create:
  name: "South 40 - County road 15"
  lat: 42.0180
  lng: -93.6100
  checkin_radius_m: 200
  idempotency_key: "loc-field-2"
  → location_id: 9202, pin_quality: "client"

event_create:
  location_id: 9202
  title: "Scout - South 40"
  start_date: "2026-09-08"
  end_date:   "2026-11-06"
  idempotency_key: "event-field-2-20260908"
  → event_id: 7202

form_assign: form_id 501, event_id 7202, idempotency_key "assign-scout-record-7202"

sqlite_execute:
  UPDATE fields SET zensched_location_id = 9202, zensched_event_id = 7202, event_valid_until = '2026-11-06'
  WHERE field_id = 2;
```

> Added Chen Family Farm, South 40 (soy, 40 ac). One-off disease scout at $180, Tuesday Sep 8 at 9:00. Same Scout Record — Priya will mark Disease. This is not a written recommendation, receituário, or NAPIS filing; if Maya wants a rec, that's still your letterhead. Approach note is local only. The ZenSched label is "South 40 - County road 15" — no grower name.

## "Invite Priya Shah, priya@example.com, and make her the default. Set the check-in radius to 300 m."

> Inviting a scout costs $0.25. I'll also widen the check-in radius to 300 m on the policy (not on the fields) so a walk-in from the corner still verifies. OK?

Owner: *"yes"*

```
worker_invite:
  email: "priya@example.com"
  first_name: "Priya"
  last_name: "Shah"
  idempotency_key: "worker-priya@example.com"
  → worker_id: 601, status: "invited", invitation_sent: true
    billing: { meter: "worker_invite", units: 1, price: 0.25 }

sqlite_execute:
  INSERT INTO scouts (scout_name, email, zensched_worker_id)
  VALUES ('Priya Shah', 'priya@example.com', 601);
  → lastInsertRowid = 1

sqlite_execute: UPDATE settings SET value = '601' WHERE key = 'default_worker_id';

policy_get: policy_id 0
policy_update:
  policy_id: 0
  settings_json: '{"geofence_enabled": true, "require_on_site": true, "checkin_radius_m": 300}'
```

The radius is on the **policy**, not on either field.

> Invited Priya. She'll get an email with the app link and an activation code. She's the default scout now. Check-in radius is 300 m on the account policy — wide enough for a corner pin plus a walk into the first 20 rows. Remember to give her Rivera's south-approach note; I keep that off ZenSched on purpose.

## "Schedule this week for Priya."

```
sqlite_query: SELECT * FROM fields_due;
  → 2026-09-07 | Tom Rivera | Rivera Farms | North 80 | corn | weekly | $125 | field_scout | 45 min
               | field 1 | evt 7201 | event_needs_roll 0 | worker 601 Priya
               | start_iso 2026-09-07T07:00:00-05:00 | end_iso 2026-09-07T07:45:00-05:00
               | shift-field-1-20260907
    2026-09-08 | Maya Chen  | Chen Family Farm | South 40 | soy | on-demand | $180 | disease_scout | 60 min
               | field 2 | evt 7202 | event_needs_roll 0 | worker 601 Priya
               | start_iso 2026-09-08T09:00:00-05:00 | end_iso 2026-09-08T10:00:00-05:00
               | shift-field-2-20260908
  (2 rows)

shift_create:
  event_id: 7201
  worker_id: 601
  start: "2026-09-07T07:00:00-05:00"
  end:   "2026-09-07T07:45:00-05:00"
  idempotency_key: "shift-field-1-20260907"
  → shift_id: 88011, status: "scheduled", forms_installed: [501]

shift_create:
  event_id: 7202
  worker_id: 601
  start: "2026-09-08T09:00:00-05:00"
  end:   "2026-09-08T10:00:00-05:00"
  idempotency_key: "shift-field-2-20260908"
  → shift_id: 88012, status: "scheduled", forms_installed: [501]
```

> Scheduled 2 walks for Priya this week:
> - Mon 9/7  7:00–7:45   Rivera Farms, North 80 (corn) — field scout
> - Tue 9/8  9:00–10:00  Chen Family Farm, South 40 (soy) — disease scout
>
> Priya has been notified in the app and both walks have the Scout Record attached. Each visit is about $0.35 once she punches in and out and you read the canopy photos ($0.10 + $0.10 + $0.15). Pass her the south-approach note yourself.

Nothing is written to SQLite here. If the owner asks "schedule this week" again, the identical idempotency keys make ZenSched return the same two shifts instead of creating duplicates.

## Priya does the work

Monday 6:58, at the SW corner of North 80, in the ZenSched app: **Check in** (GPS: 22 m from the pin, verified, $0.10). Walks the first 20 rows. Opens **Scout Record**: Growth stage = Vegetative; Pest count = 3; Pest type = Aphids; two canopy photos. Submits (no signature). **Check out** 7:41 ($0.10).

Tuesday 8:55, South 40: check in at the CR 15 corner. Scout Record: Growth stage = Flowering; Pest count = 12; Pest type = Disease; two canopy photos of the mid-canopy lesions. Check out 9:52.

## "Record this week's visits."

```
shift_list:
  date_from: "2026-09-07"
  date_to:   "2026-09-13"
  status:    "checked_out"
  → shifts: [
      { shift_id: 88011, event_id: 7201, worker_id: 601, date: "2026-09-07", start: "07:00", end: "07:45", status: "checked_out" },
      { shift_id: 88012, event_id: 7202, worker_id: 601, date: "2026-09-08", start: "09:00", end: "10:00", status: "checked_out" }
    ], count: 2

sqlite_query: SELECT zensched_shift_id FROM visits WHERE zensched_shift_id IN (88011, 88012);
  → (none; not yet recorded)

sqlite_query: SELECT field_id, grower_id, service_id, service_rate
              FROM fields WHERE zensched_event_id = 7201;
  → 1, 1, 1, 125.00
```

Agent (metered read, rule 11):

> There are 2 scout records to pull, both with canopy photos, so about $0.30 ($0.15 each). I'll read them once and keep the summaries locally. That's the last piece of the ~$0.35/visit meter (punches already billed when Priya checked in and out). OK?

Owner: *"go"*

```
form_export:
  form_id: 501
  since: "2026-09-07"
  until: "2026-09-13"
  format: "json"
  → row_count: 2, rows: [
      { submission_id: 4501, worker_id: 601, event_id: 7201, submitted_at: "2026-09-07 07:38:12",
        data: { growth_stage: "vegetative", pest_count: 3, pest_type: "aphids" },
        media: [ { cdn_url: "https://cdn.zensched.com/m/.../n1.jpg" },
                 { cdn_url: "https://cdn.zensched.com/m/.../n2.jpg" } ] },
      { submission_id: 4502, worker_id: 601, event_id: 7202, submitted_at: "2026-09-08 09:48:40",
        data: { growth_stage: "flowering", pest_count: 12, pest_type: "disease" },
        media: [ { cdn_url: "https://cdn.zensched.com/m/.../s1.jpg" },
                 { cdn_url: "https://cdn.zensched.com/m/.../s2.jpg" } ] }
    ]
    billing: { meter: "form_media", units: 2, price: 0.30 }

shift_status: shift_id 88011
  → status "checked_out", actual_in "2026-09-07T06:58:10-05:00", actual_out "2026-09-07T07:41:05-05:00",
    punches: [ { type: "in", gps_verified: true, distance_from_site_m: 22 },
               { type: "out", gps_verified: true, distance_from_site_m: 18 } ]
(free)

sqlite_execute:
  INSERT INTO visits (grower_id, field_id, service_id, completed_date, amount,
                      zensched_shift_id, zensched_event_id, zensched_worker_id,
                      actual_in, actual_out, duration_minutes, gps_verified, report_dc_id,
                      growth_stage, pest_count, pest_type, photo_urls)
  VALUES (1, 1, 1, '2026-09-07', 125.00,
          88011, 7201, 601,
          '2026-09-07T06:58:10-05:00', '2026-09-07T07:41:05-05:00', 43, 1, 4501,
          'Vegetative', 3, 'Aphids',
          '["https://cdn.zensched.com/m/.../n1.jpg","https://cdn.zensched.com/m/.../n2.jpg"]');
  -- trigger: fields.next_service_date for North 80 → 2026-09-14 (+7 days)
  -- trigger: visits.scout_id → 1 (Priya)

sqlite_execute:
  INSERT INTO visits (grower_id, field_id, service_id, completed_date, amount,
                      zensched_shift_id, zensched_event_id, zensched_worker_id,
                      actual_in, actual_out, duration_minutes, gps_verified, report_dc_id,
                      growth_stage, pest_count, pest_type, photo_urls)
  VALUES (2, 2, 2, '2026-09-08', 180.00,
          88012, 7202, 601,
          '2026-09-08T08:55:02-05:00', '2026-09-08T09:52:18-05:00', 57, 1, 4502,
          'Flowering', 12, 'Disease',
          '["https://cdn.zensched.com/m/.../s1.jpg","https://cdn.zensched.com/m/.../s2.jpg"]');
  -- trigger: fields.next_service_date for South 40 → NULL (on-demand)
```

> Recorded 2 visits, both GPS-verified.
>
> **Pressure — Tuesday, Chen South 40:** Priya marked Flowering / **Disease / 12**. Two canopy photos. This is not a written rec, receituário, or NAPIS filing; if Maya wants one, that's still on you.
>
> Rivera North 80: Vegetative / Aphids / 3. Next due Sep 14. Chen's on-demand date is cleared.

## "Scout log for last week."

```
sqlite_query: SELECT * FROM scout_log WHERE scout_date BETWEEN '2026-09-07' AND '2026-09-13';
  → 2026-09-08 | South 40 | soy | Maya Chen | Flowering | Disease | 12 | Priya Shah
    2026-09-07 | North 80 | corn | Tom Rivera | Vegetative | Aphids | 3 | Priya Shah
```

> Your copy from the Scout Record — not a recommendation, not a receituário or official agronomic prescription, not a NAPIS filing, and not a spray log:
>
> | Date | Field | Crop | Stage | Pest | Count | Scout |
> |---|---|---|---|---|---|---|
> | Sep 8 | South 40 | soy | Flowering | Disease | 12 | Priya Shah |
> | Sep 7 | North 80 | corn | Vegetative | Aphids | 3 | Priya Shah |
>
> Keep whatever you put on letterhead separately.

## "Draft invoices for everyone with uninvoiced work."

```
sqlite_query: SELECT * FROM visits_to_invoice;
  → Maya Chen    | 1 visit | 180.00 | 2026-09-08 .. 2026-09-08
    Tom Rivera   | 1 visit | 125.00 | 2026-09-07 .. 2026-09-07

sqlite_execute:
  INSERT INTO invoices (grower_id, invoice_date, due_date, total_amount, line_items)
  SELECT v.grower_id, date('now'),
         date('now', '+' || (SELECT value FROM settings WHERE key = 'invoice_due_days') || ' days'),
         SUM(v.amount),
         json_group_array(json_object('visit_id', v.visit_id, 'date', v.completed_date, 'service', s.service_name,
                                      'field', f.field_name, 'amount', v.amount, 'shift_id', v.zensched_shift_id,
                                      'stage', v.growth_stage, 'pest', v.pest_type, 'count', v.pest_count))
  FROM visits v JOIN services s ON s.service_id = v.service_id JOIN fields f ON f.field_id = v.field_id
  WHERE v.invoiced = 0 AND v.grower_id = 1 GROUP BY v.grower_id;

sqlite_execute: UPDATE visits SET invoiced = 1 WHERE invoiced = 0 AND grower_id = 1;
sqlite_query:   SELECT invoice_number, invoice_date, due_date, total_amount FROM invoices WHERE invoice_id = last_insert_rowid();
  → INV-2026-0001 | 2026-09-08 | 2026-09-22 | 125.00     (number assigned by trigger)

(same three statements for grower 2 → INV-2026-0002, 180.00)
```

The agent then writes the invoices out as text:

> Here are your two invoices. Paste each into an email or text.
>
> ```
> Prairie Scout
> Invoice INV-2026-0001
> To: Tom Rivera / Rivera Farms (tom@example.com)
> Date: Sep 8, 2026    Due: Sep 22, 2026
>
>   Sep 7    Field scout, North 80    $125.00
>
> Total due: $125.00
> Visit GPS-verified at the field corner.
> Not a spray order, receituário, official agronomic prescription, or NAPIS filing.
> ```
>
> ```
> Prairie Scout
> Invoice INV-2026-0002
> To: Maya Chen / Chen Family Farm (maya@example.com)
> Date: Sep 8, 2026    Due: Sep 22, 2026
>
>   Sep 8    Disease scout, South 40    $180.00
>
> Total due: $180.00
> Visit GPS-verified at the field corner.
> Not a spray order, receituário, official agronomic prescription, or NAPIS filing.
> ```
>
> Say "sent" when they're out and I'll note the date.

## "Sent. Tom already paid."

```
sqlite_execute: UPDATE invoices SET sent_date = date('now') WHERE invoice_number IN ('INV-2026-0001', 'INV-2026-0002');
sqlite_execute: UPDATE invoices SET paid = 1, paid_date = date('now') WHERE invoice_number = 'INV-2026-0001';
```

> Marked both sent and INV-2026-0001 paid. Chen's $180 (INV-2026-0002) is outstanding, due Sep 22.

## Eight weeks later: "Schedule this week."

US Central DST ended the first Sunday of November (2026-11-01). Ames is now `-06:00`. Brazil and India would skip this step.

```
sqlite_execute: UPDATE settings SET value = '-06:00' WHERE key = 'timezone_offset';

sqlite_query: SELECT * FROM fields_due;
  → 2026-11-09 | Tom Rivera | North 80 | weekly | evt 7201 | event_valid_until 2026-11-05 | event_needs_roll 1
               | start_iso 2026-11-09T07:00:00-06:00 | end_iso 2026-11-09T07:45:00-06:00
               | shift-field-1-20261109

event_create:
  location_id: 9201
  title: "Scout - North 80"
  start_date: "2026-11-09"
  end_date:   "2027-01-07"
  idempotency_key: "event-field-1-20261109"
  → event_id: 7301

form_assign: form_id 501, event_id 7301, idempotency_key "assign-scout-record-7301"
sqlite_execute: UPDATE fields SET zensched_event_id = 7301, event_valid_until = '2027-01-07' WHERE field_id = 1;

shift_create: event_id 7301, worker_id 601, start "2026-11-09T07:00:00-06:00",
              end "2026-11-09T07:45:00-06:00", idempotency_key "shift-field-1-20261109"
```

> Scheduled Rivera North 80 for Mon Nov 9 7:00 (`-06:00` after the clocks changed). The ZenSched event was about to expire (Nov 5), so I renewed it through Jan 7 — still a 60-day window, not a 90-day season event. Chen has no next date (on-demand) so South 40 is not on this week's list.

## Seasonal +90: "Add a seasonal tissue sample on the Bottom 40, next walk 2026-09-07."

Local cadence is +90 after each recorded visit. The ZenSched event is still `start + 59 days`. After the Sep 7 walk is recorded, `next_service_date` becomes `2026-12-06`. That date is past `event_valid_until`, so the next schedule **rolls a new event** (`event-field-{id}-20261206`) — it does not stretch the first event to 90 days, and the new shift key is `shift-field-{id}-20261206` (no collision with `…-20260907`).

## Summary of who stored what

| Thing | Where | Why |
|---|---|---|
| Tom's contact, $125 weekly cadence on North 80, Chen's one-off $180, prices | SQLite | CRM; ZenSched does not model rates or recurrence |
| South-approach note, CCA license | SQLite **only** | Privacy; never sent to ZenSched |
| Each field's GPS corner | ZenSched (integer ID in `fields`) plus `corner_lat` / `corner_lng` locally | Needed for geofenced check-in |
| Each field's current ≤60-day event and its end date | ZenSched (integer ID + `event_valid_until` in `fields`) | Shifts hang off events; renewed by the agent |
| The Scout Record form | ZenSched (ID in `settings`) | Installed on the scout's phone per shift |
| Priya, her invite, her app | ZenSched (integer ID in `scouts`) | Workforce and notifications |
| The week's two shifts | ZenSched only | Live schedule; never copied |
| GPS punches, actual times | ZenSched only | Verified record; queried via `shift_status` / `timesheet_export` |
| Two scout records with canopy photos | ZenSched (originals); summary + photo URLs in `visits` | Read once (metered), then scout log / invoices from SQLite |
| Two `visits` rows referencing shift and submission IDs | SQLite | Billing + scout-log extract |
| Two invoices, one paid | SQLite | Billing |
