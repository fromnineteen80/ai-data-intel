# AI Data Intelligence Platform — Build Specification
### Phase 1 · Pre-Money · Claude Code

---

## Read First

Before writing any code, read these files in this order:

1. `RULES.md` — operating rules that govern every decision in this build
2. `PIPELINE.md` — the strategic context for what is being built and why
3. `SCHEMA.md` — the complete database skeleton for all phases
4. `venture_pitch.md` — the investor-facing product and market thesis
5. `enterprise_pitch.md` — the enterprise client pitch and value argument
6. This file — the build sequence, step by step

Do not skip this. Do not assume prior session context carried over. Every session starts with these six files.

---

## What This Repo Is

This is the build specification and reference documentation for an AI-powered data intelligence platform. The platform serves enterprise organizations — their government affairs, communications, marketing, legal, public affairs, and adjacent teams — by unifying fragmented departmental intelligence into a single data lake with a shared longitudinal model.

**The following files are client-facing reference documents. Do not modify them. Do not treat them as application code:**
- `stack.html` — product architecture and data acquisition cost reference
- `pricing.html` — pricing matrix for client conversations
- `impact.html` — animated visualization of the intelligence and deployment stacks
- `ai_transition_pipeline_full.html` — strategic pipeline overview for client and investor conversations
- `PIPELINE.md` — the canonical written pipeline specification
- `venture_pitch.md` — investor pitch
- `enterprise_pitch.md` — enterprise client pitch
- `ai_transition_issues.md` — full issues framework

---

## What We Are Building

A data intelligence platform with six products, deployed on Vercel with Supabase as the database:

1. **Database** — the data lake. Supabase with PostGIS. Full schema across all phases. Phase 1 ingestion pipelines for all free public sources.
2. **Voter File** — queryable layer on top of normalized voter registration and audience data.
3. **Stakeholder Mapping** — Claude-powered interface for profiling policymakers, organizations, and communities using enriched district-level data.
4. **Survey Tool** — online survey instrument that collects responses and automatically overlays congressional district context from the lake on every submission.
5. **MCP Server** — Model Context Protocol server exposing the platform's data to external Claude workflows.
6. **Skills and Agents** — specialized Claude agents for legislative monitoring, stakeholder scoring, district briefs, and survey synthesis.

---

## Technology Stack

- **Frontend and Deployment:** Vercel
- **Database:** Supabase (PostgreSQL + PostGIS)
- **AI:** Anthropic Claude API — model: `claude-sonnet-4-20250514`
- **MCP:** Model Context Protocol server
- **Data:** All Phase 1 sources are public and free

---

## The Data Model

The platform is built on **organizations**, not clients. Read SCHEMA.md Section 1 before touching Supabase.

One organization is the billing and data entity. Organizations have members with org-level roles. Members belong to one or more teams within the org. Teams map to departments — government affairs, communications, legal, marketing — but all teams draw from the same data lake. Teams are scoped workflows, not data silos. The silo is broken at the data layer. Teams exist to scope permissions and workflows, not to fragment intelligence.

**Permission hierarchy:**
- `owner` — full access. Delete authority. Creates and deletes teams. Manages billing. Invites anyone at any role.
- `admin` — creates and deletes teams. Invites members. Full data access. Cannot delete the org or remove the owner.
- `analyst` — full read and write on platform products. Cannot manage members or teams.
- `viewer` — read only.
- `guest` — externally invited. Scoped to specific teams only. Cannot see org-wide data or other teams.

A solo user is an org of one. The model is identical whether the org has one member or a hundred. A consultant invited into a client org gets a membership with a role and optional team pre-assignment in a single invitation action.

Billing is always at the organization level. Teams never bill separately.

There is no `clients` table. The entity is `organizations`. All references in this codebase use `org_id`.

---

## Build Sequence

Build in this exact order. Each step depends on the one before it. After completing each step, run the pre-commit checklist before merging to main.

---

### Step 1 — Supabase Project Initialization

- Create Supabase project
- Enable PostGIS: `create extension if not exists postgis;`
- Enable UUID: `create extension if not exists "uuid-ossp";`
- Set up service role key for server-side ingestion — environment variable only, never in code
- Configure: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_KEY`, `ANTHROPIC_API_KEY`

**Pre-commit checklist — Step 1:**
- [ ] PostGIS and UUID extensions confirmed active in Supabase dashboard
- [ ] No credentials in code — all in environment variables
- [ ] No fake or placeholder data anywhere
- [ ] RULES.md reviewed — no violations
- [ ] Commit: `[supabase] initialize project with PostGIS and UUID extensions`

---

### Step 2 — Full Schema Deployment

Deploy the complete schema from SCHEMA.md to Supabase. All sections. All phases. Empty tables for Phase 2 and 3 are correct. A partial schema is not acceptable. The full skeleton must exist before any ingestion pipeline runs.

**Deploy in this order to respect foreign key dependencies:**
1. `organizations`
2. `profiles`
3. `org_memberships`, `teams`, `team_memberships`, `invitations`
4. `sessions`, `audit_log`, `notifications`, `user_preferences`
5. `subscriptions`, `add_ons`, `invoices`, `payment_methods`, `usage_events`
6. `api_keys`, `webhooks`, `webhook_deliveries`
7. `congressional_districts`, `state_leg_districts_upper`, `state_leg_districts_lower`
8. `counties`, `tracts`, `precincts`
9. `zip_to_district`
10. All Phase 1 data tables (legislation, legislative_votes, fec_candidates, fec_committees, fec_filings, bls_workforce, acs_demographics, cdc_places, cdc_svi, hud_housing, crime_data, education_data, pew_benchmarks)
11. All Phase 2 placeholder tables (audience_segments, workforce_movement, voter_file, voter_lists, voter_list_exports, polling_waves, polling_responses, polling_toplines)
12. All Phase 3 placeholder tables (consumer_intelligence, labor_market, health_utilization, cms_claims)
13. All platform product tables (stakeholders, stakeholder_scores, stakeholder_tags, stakeholder_interactions, surveys, survey_responses, survey_exports, survey_templates, survey_versions, scorecards, scorecard_metrics, scorecard_results, reports, documents, data_exports, time_series_snapshots, client_data_access, pac_intelligence, institute_publications, grassroots_campaigns, grassroots_actions, issue_watchlists, district_briefs, issue_alerts, saved_searches)
14. MCP and agent tables (mcp_tools, mcp_queries, agents, agent_runs)
15. Ingestion infrastructure tables (ingestion_runs, ingestion_errors)

After deploying: write RLS policies for every table in Sections 1 and 6 of SCHEMA.md before any client data is written. Public data tables (Sections 3, 4, 5) do not require RLS.

TBD columns in SCHEMA.md are deployed as-is — no columns are added until real data inspection confirms them.

**Pre-commit checklist — Step 2:**
- [ ] All 78 tables exist in Supabase — verified against full list in SCHEMA.md
- [ ] RLS enabled on every org-scoped table in Sections 1 and 6
- [ ] No TBD columns filled in speculatively
- [ ] No columns exist in Supabase that are not in SCHEMA.md
- [ ] All foreign key relationships resolve — no broken references
- [ ] Service role confirmed to bypass RLS
- [ ] Anon key confirmed to respect RLS
- [ ] RULES.md reviewed — no violations
- [ ] Commit: `[schema] deploy full platform schema across all phases`

---

### Step 3 — Geographic Foundation

The geographic lookup is the backbone every ingestion pipeline and every survey submission depends on. Nothing else runs until this is complete and verified with real data.

**3a — Download and inspect TIGER/Line shapefiles**
- Source: https://www.census.gov/geographies/mapping-files/time-series/geo/tiger-line-file.html
- Download: Congressional Districts, ZCTAs, State Legislative Districts (upper and lower), Counties, Census Tracts
- Inspect the actual shapefile attribute tables before writing any code
- Update SCHEMA.md Section 2 with confirmed column names from real inspection
- Load into PostGIS using `shp2pgsql` or `ogr2ogr`
- Do not invent field names. Use what the files actually contain.

**3b — Build ZIP to congressional district lookup**
- Every ingestion table and every survey submission resolves ZIP to congressional district through this function
- Test with real ZIP codes — confirm results against known geographies
- A ZIP that does not resolve is logged to `ingestion_errors`, not silently dropped or written with a null district

**3c — Verify**
- Run a point-in-polygon query against a known ZIP and confirm the returned district is correct
- Do not proceed to Step 4 until this passes with real data

**Pre-commit checklist — Step 3:**
- [ ] Shapefiles inspected — SCHEMA.md Section 2 updated with real column names before any code was written
- [ ] All geographic tables populated with real Census data
- [ ] ZIP-to-district lookup tested with real ZIP codes and correct results confirmed
- [ ] At least one point-in-polygon query verified against a known geography
- [ ] No invented field names anywhere
- [ ] RULES.md reviewed — no violations
- [ ] Commit: `[geo] load TIGER/Line shapefiles and build ZIP-to-district lookup`

---

### Step 4 — Phase 1 Data Ingestion Pipelines

All data is real. No fabricated or mocked records anywhere. If a source requires registration or an API key, log it in NOTES.md and wait for credentials before writing the ingestion script.

For each source: download a real sample, inspect it, update SCHEMA.md with confirmed columns, write the migration, then write the ingestion script. This order is non-negotiable. Every script follows the ingestion pipeline pattern from RULES.md Rule 9 — upsert only, idempotent, logs to `ingestion_runs`, errors to `ingestion_errors`.

**4a — Congress.gov API**
- Register: https://api.congress.gov/sign-up/
- Inspect real API response first
- Tables: `legislation`, `legislative_votes`

**4b — FEC Data**
- Bulk: https://www.fec.gov/data/browse-data/?tab=bulk-data
- API: https://api.open.fec.gov
- Inspect real bulk CSV files first
- Tables: `fec_candidates`, `fec_committees`, `fec_filings`

**4c — LegiScan**
- Register: https://legiscan.com/legiscan
- Inspect real API response first
- Table: `legislation` (same table as Congress.gov, different `source` value)
- Free tier weekly snapshot is sufficient for Phase 1

**4d — BLS Microdata**
- CPS: https://www.bls.gov/cps/data.htm
- QCEW: https://www.bls.gov/cew/downloadable-data.htm
- OEWS: https://www.bls.gov/oes/tables.htm
- Fixed-width and CSV — inspect real files first
- Table: `bls_workforce`
- Download selectively by series — do not bulk load without scoping first

**4e — ACS / Census PUMS**
- API: https://api.census.gov
- PUMS: https://www.census.gov/programs-surveys/acs/microdata.html
- Inspect real API response and PUMS file headers first
- Table: `acs_demographics`
- Use Census API for targeted queries — PUMS files are large

**4f — CDC PLACES**
- Socrata API: https://chronicdata.cdc.gov
- Inspect real API response first
- Table: `cdc_places`

**4g — CDC Social Vulnerability Index**
- Download: https://www.atsdr.cdc.gov/placeandhealth/svi/data_documentation_download.html
- Inspect real CSV first
- Table: `cdc_svi`

**4h — HUD Housing**
- FMR: https://www.huduser.gov/portal/datasets/fmr.html
- CHAS: https://www.huduser.gov/portal/datasets/cp.html
- Inspect real files first
- Table: `hud_housing`

**4i — FBI NIBRS**
- Download: https://crime-data-explorer.fr.cloud.gov/pages/downloads
- Inspect real CSV first
- Table: `crime_data`

**4j — BJS NCVS**
- ICPSR account required: https://www.icpsr.umich.edu
- Format: SPSS — convert to CSV after download
- Inspect real file first
- Table: `crime_data` (same table, different `source` value)

**4k — NCES Common Core of Data**
- Download: https://nces.ed.gov/ccd/
- Inspect real CSV first
- Table: `education_data`

**4l — IPEDS**
- Download: https://nces.ed.gov/ipeds/use-the-data
- Inspect real CSV first
- Table: `education_data` (same table, different `source` value)

**4m — Pew Research Center**
- Register: https://www.pewresearch.org/datasets/
- Format: SPSS — convert to CSV after download
- Request specific datasets by name. Do not bulk download.
- Inspect real microdata file first
- Table: `pew_benchmarks`

**Pre-commit checklist — Step 4 (run after each source, not just at the end):**
- [ ] Source data downloaded and inspected before any code was written
- [ ] SCHEMA.md updated with confirmed column names before migration was written
- [ ] Migration written and applied before ingestion script was written
- [ ] Ingestion script uses upsert with conflict resolution on natural key
- [ ] Every record has a resolved `congressional_district_id` — no unmatched records written
- [ ] Ingestion run logged to `ingestion_runs` with accurate record counts
- [ ] Failed records logged to `ingestion_errors` with raw record preserved
- [ ] No invented field names anywhere
- [ ] No fake or mock data anywhere
- [ ] RULES.md reviewed — no violations
- [ ] Commit: `[ingestion] {source_name} — {N} records`

---

### Step 5 — Survey Tool

The survey tool is the first client-facing product and the first deliverable for the anchor client.

**Requirements:**
- Deployable at a custom URL on Vercel
- Question types: multiple choice, Likert scale, open text, ranked choice
- Branching logic driven by response values
- ZIP code required on every submission
- On submission: resolve ZIP to congressional district, write response and district context in a single atomic transaction
- A failed enrichment does not produce a stored response without context
- A ZIP that does not resolve returns a clear validation error — no unmatched records written
- Survey structure stored in `surveys` table — new surveys are created by inserting a record, not deploying code
- Survey templates available in `survey_templates`
- Version history written to `survey_versions` on every publish
- Organization dashboard showing aggregated results with district-level context

**Auth:**
- Respondents need no account
- Dashboard requires `viewer` role minimum
- Survey creation and publication requires `analyst` or above
- Survey deletion requires `admin` or `owner`

**Pre-commit checklist — Step 5:**
- [ ] Submission writes atomically — response and enrichment in one transaction
- [ ] Failed enrichment does not produce a stored response
- [ ] ZIP validation runs before any database write
- [ ] Unmatched ZIPs return a clear error and are not written
- [ ] Survey structure is in the database, not hardcoded
- [ ] Dashboard shows real data — no mock data
- [ ] Auth gates correct for each action
- [ ] Version history written on publish
- [ ] RULES.md reviewed — no violations
- [ ] Commit: `[survey] survey tool — create, publish, respond, dashboard`

---

### Step 6 — Stakeholder Mapping Interface

- Search by name, organization, or geography
- Profile built from real ingested data: FEC, BLS, ACS, legislative
- Claude API synthesizes into a plain-language brief
- Score written to `stakeholder_scores`, profile to `stakeholders`, interactions to `stakeholder_interactions`
- No fabricated profiles, no placeholder scores

**Auth:**
- Create and score stakeholders: `analyst` or above
- View stakeholder profiles: `viewer` or above
- Guests see only teams they are assigned to

**Pre-commit checklist — Step 6:**
- [ ] All stakeholder data sourced from real ingested records
- [ ] No fabricated scores or placeholder profiles
- [ ] Scores written to `stakeholder_scores` with `scored_by: agent`
- [ ] Auth gates correct per role
- [ ] RULES.md reviewed — no violations
- [ ] Commit: `[stakeholders] stakeholder mapping — search, score, profile`

---

### Step 7 — MCP Server

- Build using the MCP SDK
- Deploy as a separate Vercel function
- Authenticate via `api_keys` table — hash only, never plaintext
- Log every query to `mcp_queries`

**Tools (one tool, one responsibility):**
- `get_district_profile` — enriched profile for a congressional district
- `search_legislation` — search by keyword, status, state, or district
- `get_stakeholder_brief` — scored stakeholder profile
- `query_survey_results` — aggregated survey results for a district or org
- `get_issue_alerts` — active alerts for an org's watchlists

Each tool validates inputs before querying. Each tool has a precise single-sentence description. Tools do not call other tools.

**Pre-commit checklist — Step 7:**
- [ ] Each tool does exactly one thing
- [ ] Each tool validates inputs before any database query
- [ ] Each tool has a precise single-sentence description
- [ ] API key authentication works — no unauthenticated queries reach the database
- [ ] Every query logged to `mcp_queries`
- [ ] No tool calls another tool
- [ ] RULES.md reviewed — no violations
- [ ] Commit: `[mcp] MCP server — {N} tools deployed`

---

### Step 8 — Skills and Agents

Each agent is a defined task workflow. Defined inputs. Defined tool sequence. Defined output written to Supabase. Not a chatbot.

**Legislative Monitor** — input: keywords, target districts, org ID. Output: issue alerts written to `issue_alerts`.

**Stakeholder Scorer** — input: stakeholder ID, org ID. Output: score to `stakeholder_scores`, brief to `district_briefs`.

**District Brief** — input: district ID, org ID. Output: brief to `district_briefs` with `data_snapshot`.

**Survey Synthesis** — input: survey ID, org ID. Output: report written to `reports` as type `survey_analysis`.

All four agents log to `agent_runs` with status, duration, and token count. All output is sourced from real ingested records.

**Pre-commit checklist — Step 8:**
- [ ] Each agent has defined inputs, tool sequence, and output
- [ ] Every agent run logged to `agent_runs`
- [ ] No output from fabricated data — all sourced from real records
- [ ] Output written to the correct table
- [ ] RULES.md reviewed — no violations
- [ ] Commit: `[agents] {agent_name} — {description}`

---

## Schema

The complete database schema is in `SCHEMA.md`. Read it before touching Supabase. It covers all 78 tables across 8 sections. Deploy the full schema at Step 2 before any ingestion runs. Update SCHEMA.md before writing any migration. Never add columns that have not been confirmed from real data inspection.

---

## Deployment

- All code deploys to Vercel
- MCP server deploys as a separate Vercel function
- Environment variables: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_KEY`, `ANTHROPIC_API_KEY`
- Survey tool is the first URL to go live

---

## Out of Scope for Phase 1

- Website — the placeholder site is temporary. Pitch deck and real website come after the platform is built.
- AI chat assistant — deferred
- Tunnl — Phase 2
- Revelio Labs — Phase 2
- Experian ConsumerView — Phase 3
- Lightcast — Phase 3
- Symphony Health — Phase 3
- Proprietary polling waves — Phase 2
- State legislative district overlay — schema exists, data and UI are Phase 2

---

## Strategic Context

Start with PIPELINE.md. The intelligence stack layers map to the acquisition phases. The six connection-layer products are the six products built here. The HTML files are finished client-facing documents — do not modify them.
