# NOTES.md — Blocker and Decision Log

Per RULES.md Rule 12 and Rule 15, every blocker, unresolved requirement, or
decision that requires human action is logged here. Nothing is silently
skipped. Nothing is worked around.

---

## Active Blockers — Require Human Action Before Next Step Proceeds

### B1 — Supabase project does not yet exist (Step 1)

BUILD.md Step 1 requires creating a Supabase project, enabling PostGIS and
`uuid-ossp` in its dashboard, and wiring the service role key. The Claude Code
session cannot create a Supabase account, provision a project, or fetch
`SUPABASE_URL` / `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_KEY` on its own.

**Human action required:**
1. Create Supabase project at https://supabase.com
2. Run the migrations in `supabase/migrations/` in numeric order against the
   project (either via `supabase db push` with the Supabase CLI, or by pasting
   each file into the SQL editor in order)
3. Populate `.env` locally from `.env.example` with the real values
4. Configure the same four env vars in Vercel project settings when the first
   deploy is prepared

The migration files in this repo are the deliverable for Step 1 and Step 2.
They are written to match SCHEMA.md exactly. Applying them against a live
Supabase instance completes the pre-commit checklists for those steps.

### B2 — No API credentials for Phase 1 sources (Step 4)

Per Rule 15, ingestion scripts must not be written against guessed API response
shapes. The following sources require registration before any ingestion code
can be written, and registration requires a human:

| Source               | Registration URL                                                    | Required for  |
| -------------------- | ------------------------------------------------------------------- | ------------- |
| Congress.gov API     | https://api.congress.gov/sign-up/                                   | Step 4a       |
| FEC Open Data API    | https://api.open.fec.gov (api.data.gov key)                         | Step 4b       |
| LegiScan             | https://legiscan.com/legiscan                                       | Step 4c       |
| Census API           | https://api.census.gov/data/key_signup.html                         | Step 4e       |
| Socrata (CDC PLACES) | https://chronicdata.cdc.gov/signup (app token, not strictly req'd)  | Step 4f       |
| ICPSR (BJS NCVS)     | https://www.icpsr.umich.edu                                         | Step 4j       |
| Pew Research Center  | https://www.pewresearch.org/datasets/                               | Step 4m       |
| Anthropic API        | https://console.anthropic.com                                       | Steps 6, 7, 8 |

When each key is provided, add it to `.env.example` with a placeholder and to
the local `.env`, then proceed with the corresponding Step 4 substep.

### B3 — TIGER/Line shapefiles not yet inspected (Step 3)

BUILD.md Step 3 and RULES.md Rule 15 both require real inspection of the
Census TIGER/Line shapefiles before any code is written against them and
before the TBD columns in SCHEMA.md Section 2 are filled in. The files are
large (hundreds of MB); downloading and loading them into PostGIS happens
after the Supabase project exists (B1) and ideally on a machine where
`shp2pgsql` or `ogr2ogr` is installed.

**Not started.** Step 3 is the next unblocked step after B1 resolves.

---

## Schema Observations — Flagged, Not Resolved

### O1 — Table count discrepancy in BUILD.md Step 2 checklist

BUILD.md Step 2 pre-commit checklist states: "All 78 tables exist in Supabase
— verified against full list in SCHEMA.md."

The ordered deployment list in the same section (items 1–15) enumerates 81
tables. Counting the CREATE TABLE statements in SCHEMA.md also yields 81.

Counts by section:
- Section 1 (auth/orgs/teams/billing): 18
- Section 2 (geographic reference): 7
- Section 3 (Phase 1 public data): 13
- Section 4 (Phase 2 placeholders): 8
- Section 5 (Phase 3 placeholders): 4
- Section 6 (platform products): 25
- Section 7 (MCP + agents): 4
- Section 8 (ingestion infrastructure): 2
- **Total: 81**

The migration files in this repo create all 81 tables that SCHEMA.md defines.
Human decision required on whether the "78" in BUILD.md is a stale count to
be updated, or whether three tables should be removed from SCHEMA.md. Not
resolved unilaterally — Rule 12.

---

## Audit Log — Schema Audits per RULES.md Rule 16

No ingestion has occurred yet. First audit entry will be written when Step 3
(geographic foundation) begins with real TIGER/Line inspection.

---

## Out of Scope Reminders (RULES.md Rule 3)

Do not build, do not scaffold for, do not write placeholder tables beyond
SCHEMA.md for:
- AI chat assistant or conversational UI
- Tunnl audience infrastructure (Phase 2)
- Revelio Labs (Phase 2)
- Experian ConsumerView (Phase 3)
- Lightcast (Phase 3)
- Symphony Health (Phase 3)
- Proprietary polling waves (Phase 2)
- State legislative district overlay data or UI (schema exists, data is Phase 2)
- Any paid data source not listed in Phase 1
