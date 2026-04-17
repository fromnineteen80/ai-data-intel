# SCHEMA.md — Full Platform Skeleton

This is the complete database skeleton for the platform. Every table that will ever exist is defined here, in the phase it becomes active. Columns marked `-- TBD` will be filled in when the actual dataset is inspected. Do not add columns speculatively outside this file. When a new column is confirmed from a real data source, add it here first, then migrate.

All tables use Supabase PostgreSQL with PostGIS. Row-level security is enabled on every table that contains client or user data. All primary keys are UUIDs. All timestamps are `timestamptz` with `default now()`.

---

## Conventions

```
id          uuid primary key default gen_random_uuid()
created_at  timestamptz default now()
updated_at  timestamptz default now()  -- on tables that change over time
org_id      uuid references organizations(id)  -- on every client-scoped table
ingested_at timestamptz default now()  -- on every data ingestion table
raw         jsonb  -- original source record, always preserved
```

Geographic district format: `{STATE}-{DISTRICT}` e.g. `PA-12`, `TX-07`, `CA-33`.
At-large districts: `{STATE}-00` e.g. `AK-00`, `WY-00`.

---

## Section 1 — Authentication, Organizations, Teams, and Billing

The ownership model: one **organization** is the billing and data entity. Organizations have **members** with org-level roles. Members belong to one or more **teams** within the org. Teams are how departments use the shared intelligence differently — government affairs runs stakeholder mapping, comms runs messaging tools, legal monitors legislation — but they all draw from the same data lake. The silo is broken at the data layer. Teams exist only to scope workflows and permissions, not to fragment the intelligence.

A solo user (an individual consultant, for example) is an org of one. The model is identical — they just have no other members. When that consultant is invited into a client org, they get a membership with scoped team access. They see only what they are given. The data lake underneath is still unified.

**Permission hierarchy:**
- `owner` — created the org. Full access. Can delete the org, manage billing, create and delete teams, invite anyone at any role, and remove any member including admins.
- `admin` — can create and delete teams, invite members at any role below admin, manage team assignments, and access all data.
- `analyst` — full read and write access to platform products. Cannot manage members or teams.
- `viewer` — read-only access to org data and reports.
- `guest` — invited externally (e.g. a consultant). Access scoped to specific teams only. Cannot see org-wide data or other teams.

```sql
-- Supabase Auth manages auth.users natively.
-- All application-level identity extends from profiles.

profiles (
  id                    uuid primary key references auth.users(id) on delete cascade,
  full_name             text,
  avatar_url            text,
  phone                 text,
  timezone              text default 'America/New_York',
  last_seen_at          timestamptz,
  onboarding_complete   boolean default false,
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
  -- Note: org role and department live in org_memberships, not here.
  -- A user may belong to multiple orgs with different roles in each.
)

organizations (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null,
  slug                  text unique not null,
  type                  text,
  -- types: corporate, political, consulting, nonprofit, individual
  tier                  text not null default 'base',
  -- tiers: base, polling, full
  status                text not null default 'active',
  -- statuses: trial, active, suspended, churned
  owner_id              uuid references profiles(id),
  billing_email         text,
  domain                text,
  logo_url              text,
  settings              jsonb default '{}',
  -- org-wide settings: default district, data access preferences, notification defaults
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
)

org_memberships (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id) on delete cascade,
  user_id               uuid references profiles(id) on delete cascade,
  role                  text not null default 'viewer',
  -- roles: owner, admin, analyst, viewer, guest
  department            text,
  -- optional: self-reported or admin-assigned department label
  title                 text,
  joined_at             timestamptz default now(),
  invited_by            uuid references profiles(id),
  created_at            timestamptz default now(),
  updated_at            timestamptz default now(),
  unique(org_id, user_id)
)

teams (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id) on delete cascade,
  created_by            uuid references profiles(id),
  name                  text not null,
  description           text,
  function              text,
  -- function: government_affairs, communications, marketing, legal, policy,
  --           public_affairs, community_relations, digital, sustainability,
  --           foundation, strategy, analytics, political_action, executive
  -- The function field maps to the deployment stack in PIPELINE.md.
  -- Teams are not siloed from the data. They are scoped views of the same lake.
  data_focus            text[],
  -- array of issue areas or datasets this team primarily works with
  settings              jsonb default '{}',
  created_at            timestamptz default now(),
  updated_at            timestamptz default now(),
  unique(org_id, name)
)

team_memberships (
  id                    uuid primary key default gen_random_uuid(),
  team_id               uuid references teams(id) on delete cascade,
  user_id               uuid references profiles(id) on delete cascade,
  org_id                uuid references organizations(id),
  -- denormalized for RLS efficiency
  role                  text not null default 'member',
  -- roles: lead, member
  -- team role is additive to org role, not a replacement
  added_by              uuid references profiles(id),
  created_at            timestamptz default now(),
  unique(team_id, user_id)
)

invitations (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id) on delete cascade,
  invited_by            uuid references profiles(id),
  email                 text not null,
  org_role              text not null default 'viewer',
  -- org role the invitee will receive on acceptance
  team_ids              uuid[],
  -- optional: pre-assign to specific teams on acceptance
  token                 text unique not null,
  accepted_at           timestamptz,
  expires_at            timestamptz not null,
  created_at            timestamptz default now()
)

sessions (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid references profiles(id),
  org_id                uuid references organizations(id),
  ip_address            inet,
  user_agent            text,
  started_at            timestamptz default now(),
  ended_at              timestamptz,
  created_at            timestamptz default now()
)

audit_log (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  team_id               uuid references teams(id),
  user_id               uuid references profiles(id),
  action                text not null,
  -- actions: login, logout, create, update, delete, export, query, invite, remove_member
  resource_type         text,
  resource_id           uuid,
  metadata              jsonb,
  ip_address            inet,
  created_at            timestamptz default now()
)

notifications (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid references profiles(id),
  org_id                uuid references organizations(id),
  team_id               uuid references teams(id),
  type                  text not null,
  title                 text not null,
  body                  text,
  read_at               timestamptz,
  action_url            text,
  created_at            timestamptz default now()
)

user_preferences (
  id                    uuid primary key references auth.users(id) on delete cascade,
  email_notifications   boolean default true,
  digest_frequency      text default 'weekly',
  -- frequencies: realtime, daily, weekly, never
  default_district      text references congressional_districts(id),
  ui_settings           jsonb default '{}',
  updated_at            timestamptz default now()
)

-- ─── SUBSCRIPTIONS AND BILLING ───────────────────────────────────────────────
-- Billing is always at the organization level, never at the team or user level.

subscriptions (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  tier                  text not null,
  -- tiers: base, polling, full
  status                text not null,
  -- statuses: trialing, active, past_due, canceled
  billing_interval      text not null default 'monthly',
  amount_cents          integer,
  currency              text default 'usd',
  current_period_start  date,
  current_period_end    date,
  canceled_at           timestamptz,
  external_id           text,
  -- billing provider reference (Stripe or equivalent)
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
)

add_ons (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  subscription_id       uuid references subscriptions(id),
  type                  text not null,
  -- types: mcp_server, grassroots_campaign, consortium_scorecard, stakeholder_management, survey_tool
  status                text not null default 'active',
  amount_cents          integer,
  started_at            date,
  ended_at              date,
  created_at            timestamptz default now()
)

invoices (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  subscription_id       uuid references subscriptions(id),
  external_id           text,
  status                text not null,
  -- statuses: draft, open, paid, void, uncollectible
  amount_cents          integer,
  amount_paid_cents     integer,
  currency              text default 'usd',
  period_start          date,
  period_end            date,
  due_date              date,
  paid_at               timestamptz,
  invoice_url           text,
  created_at            timestamptz default now()
)

payment_methods (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  external_id           text,
  type                  text,
  -- types: card, ach, wire
  is_default            boolean default false,
  last_four             text,
  brand                 text,
  expires_at            date,
  created_at            timestamptz default now()
)

usage_events (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  team_id               uuid references teams(id),
  user_id               uuid references profiles(id),
  event_type            text not null,
  -- types: api_query, agent_run, survey_response, export, mcp_query
  quantity              integer default 1,
  metadata              jsonb,
  recorded_at           timestamptz default now()
)

-- ─── API ACCESS AND WEBHOOKS ─────────────────────────────────────────────────

api_keys (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  created_by            uuid references profiles(id),
  name                  text not null,
  key_hash              text not null,
  -- store hash only, never plaintext
  scopes                text[],
  -- scopes: read:districts, read:stakeholders, read:surveys, write:surveys, mcp:query
  last_used_at          timestamptz,
  expires_at            timestamptz,
  revoked_at            timestamptz,
  created_at            timestamptz default now()
)

webhooks (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  url                   text not null,
  events                text[],
  -- events: survey.response, alert.created, stakeholder.scored, legislation.updated
  secret_hash           text not null,
  active                boolean default true,
  last_triggered_at     timestamptz,
  created_at            timestamptz default now()
)

webhook_deliveries (
  id                    uuid primary key default gen_random_uuid(),
  webhook_id            uuid references webhooks(id),
  event_type            text not null,
  payload               jsonb,
  status_code           integer,
  response_body         text,
  delivered_at          timestamptz,
  created_at            timestamptz default now()
)
```

---

## Section 2 — Geographic Reference

Tables defined here. Column details to be filled in after inspecting real Census TIGER/Line shapefiles, the congressional district boundary files, and the ZIP code tabulation area files. Do not add columns until the actual files are downloaded and inspected.

```sql
-- Column structure TBD after inspecting:
-- https://www.census.gov/geographies/mapping-files/time-series/geo/tiger-line-file.html
-- Download: Congressional Districts, ZCTAs, State Legislative Districts, Counties, Tracts

congressional_districts (
  id                    text primary key,
  -- ID format and available fields TBD on shapefile inspection
  geom                  geometry(MultiPolygon, 4326),
  raw_attributes        jsonb,
  -- all shapefile attributes preserved here until columns are confirmed
  updated_at            timestamptz default now()
)

state_leg_districts_upper (
  id                    text primary key,
  -- TBD on shapefile inspection
  geom                  geometry(MultiPolygon, 4326),
  raw_attributes        jsonb,
  updated_at            timestamptz default now()
)

state_leg_districts_lower (
  id                    text primary key,
  -- TBD on shapefile inspection
  geom                  geometry(MultiPolygon, 4326),
  raw_attributes        jsonb,
  updated_at            timestamptz default now()
)

zip_to_district (
  zip_code              text primary key,
  congressional_district_id         text references congressional_districts(id),
  state_leg_upper_district_id       text references state_leg_districts_upper(id),
  state_leg_lower_district_id       text references state_leg_districts_lower(id),
  -- additional join fields TBD on ZCTA shapefile inspection
  updated_at            timestamptz default now()
)

counties (
  id                    text primary key,
  -- TBD on shapefile inspection
  geom                  geometry(MultiPolygon, 4326),
  raw_attributes        jsonb
)

tracts (
  id                    text primary key,
  -- TBD on shapefile inspection
  geom                  geometry(MultiPolygon, 4326),
  raw_attributes        jsonb
)

precincts (
  id                    text primary key,
  -- TBD on voter file data inspection — precinct IDs vary by state and vendor
  congressional_district_id         text references congressional_districts(id),
  state_leg_upper_district_id       text references state_leg_districts_upper(id),
  state_leg_lower_district_id       text references state_leg_districts_lower(id),
  raw_attributes        jsonb,
  updated_at            timestamptz default now()
)
```

---

## Section 3 — Phase 1 Public Data

All data columns are TBD until each source is downloaded and inspected. Each table has only the structural minimum: primary key, source identifier, geographic reference, the raw source record, and ingestion timestamp. Data columns are added to SCHEMA.md after real inspection, then migrated.

```sql
-- ─── LEGISLATIVE — Congress.gov API + LegiScan ────────────────────────────────
-- Inspect real API responses before adding any columns beyond this skeleton
-- Congress.gov: https://api.congress.gov
-- LegiScan: https://legiscan.com/legiscan

legislation (
  id                          uuid primary key default gen_random_uuid(),
  source                      text not null,    -- congress_gov, legiscan
  source_id                   text not null,    -- source's natural bill identifier, TBD field name
  congressional_district_id   text references congressional_districts(id),
  raw                         jsonb,
  ingested_at                 timestamptz default now(),
  unique(source, source_id)
)

legislative_votes (
  id          uuid primary key default gen_random_uuid(),
  bill_id     uuid references legislation(id),
  -- TBD: all columns after API inspection
  raw         jsonb,
  ingested_at timestamptz default now()
)

-- ─── CAMPAIGN FINANCE — FEC ───────────────────────────────────────────────────
-- Inspect bulk CSV files before adding any columns beyond this skeleton
-- https://www.fec.gov/data/browse-data/?tab=bulk-data

fec_candidates (
  id                          uuid primary key default gen_random_uuid(),
  source_id                   text unique not null,  -- FEC candidate ID, TBD field name
  congressional_district_id   text references congressional_districts(id),
  raw                         jsonb,
  ingested_at                 timestamptz default now()
)

fec_committees (
  id          uuid primary key default gen_random_uuid(),
  source_id   text unique not null,  -- FEC committee ID, TBD field name
  raw         jsonb,
  ingested_at timestamptz default now()
)

fec_filings (
  id                          uuid primary key default gen_random_uuid(),
  committee_id                uuid references fec_committees(id),
  candidate_id                uuid references fec_candidates(id),
  congressional_district_id   text references congressional_districts(id),
  -- TBD: all data columns after bulk file inspection
  raw                         jsonb,
  ingested_at                 timestamptz default now()
)

-- ─── WORKFORCE — BLS ─────────────────────────────────────────────────────────
-- Inspect real fixed-width and CSV files before adding any columns
-- CPS: https://www.bls.gov/cps/data.htm
-- QCEW: https://www.bls.gov/cew/downloadable-data.htm
-- OEWS: https://www.bls.gov/oes/tables.htm

bls_workforce (
  id                          uuid primary key default gen_random_uuid(),
  source                      text not null,    -- CPS, QCEW, OEWS
  congressional_district_id   text references congressional_districts(id),
  -- TBD: all data columns after file inspection
  raw                         jsonb,
  ingested_at                 timestamptz default now()
)

-- ─── DEMOGRAPHICS — ACS ──────────────────────────────────────────────────────
-- Inspect Census API response and PUMS file headers before adding any columns
-- https://api.census.gov / https://www.census.gov/programs-surveys/acs/microdata.html

acs_demographics (
  id                          uuid primary key default gen_random_uuid(),
  congressional_district_id   text references congressional_districts(id),
  -- TBD: all data columns after API and PUMS file inspection
  raw                         jsonb,
  ingested_at                 timestamptz default now()
)

-- ─── HEALTH — CDC PLACES + SVI ───────────────────────────────────────────────
-- Inspect Socrata API response before adding any columns
-- PLACES: https://chronicdata.cdc.gov
-- SVI: https://www.atsdr.cdc.gov/placeandhealth/svi/data_documentation_download.html

cdc_places (
  id                          uuid primary key default gen_random_uuid(),
  congressional_district_id   text references congressional_districts(id),
  -- TBD: all data columns after API inspection
  raw                         jsonb,
  ingested_at                 timestamptz default now()
)

cdc_svi (
  id                          uuid primary key default gen_random_uuid(),
  congressional_district_id   text references congressional_districts(id),
  -- TBD: all data columns after file inspection
  raw                         jsonb,
  ingested_at                 timestamptz default now()
)

-- ─── HOUSING — HUD + Census ──────────────────────────────────────────────────
-- Inspect real files before adding any columns
-- FMR: https://www.huduser.gov/portal/datasets/fmr.html
-- CHAS: https://www.huduser.gov/portal/datasets/cp.html

hud_housing (
  id                          uuid primary key default gen_random_uuid(),
  congressional_district_id   text references congressional_districts(id),
  -- TBD: all data columns after file inspection
  raw                         jsonb,
  ingested_at                 timestamptz default now()
)

-- ─── CRIME — FBI NIBRS + BJS NCVS ────────────────────────────────────────────
-- Inspect real files before adding any columns
-- NIBRS: https://crime-data-explorer.fr.cloud.gov/pages/downloads
-- NCVS: https://www.icpsr.umich.edu (requires free ICPSR account)

crime_data (
  id                          uuid primary key default gen_random_uuid(),
  source                      text not null,    -- NIBRS, NCVS
  congressional_district_id   text references congressional_districts(id),
  -- TBD: all data columns after file inspection
  raw                         jsonb,
  ingested_at                 timestamptz default now()
)

-- ─── EDUCATION — NCES + IPEDS ────────────────────────────────────────────────
-- Inspect real files before adding any columns
-- NCES CCD: https://nces.ed.gov/ccd/
-- IPEDS: https://nces.ed.gov/ipeds/use-the-data

education_data (
  id                          uuid primary key default gen_random_uuid(),
  source                      text not null,    -- NCES, IPEDS, CRDC
  congressional_district_id   text references congressional_districts(id),
  -- TBD: all data columns after file inspection
  raw                         jsonb,
  ingested_at                 timestamptz default now()
)

-- ─── SENTIMENT BENCHMARK — Pew Research Center ───────────────────────────────
-- Inspect SPSS microdata files before adding any columns
-- https://www.pewresearch.org/datasets/ (requires free account)

pew_benchmarks (
  id                          uuid primary key default gen_random_uuid(),
  dataset_name                text not null,    -- name of specific Pew dataset
  congressional_district_id   text references congressional_districts(id),
  -- TBD: all data columns after microdata file inspection
  raw                         jsonb,
  ingested_at                 timestamptz default now()
)
```

---

## Section 4 — Phase 2 Data (Schema Now, Data Later)

```sql
-- ─── AUDIENCE INFRASTRUCTURE ─────────────────────────────────────────────────

audience_segments (
  id                          uuid primary key default gen_random_uuid(),
  source                      text not null,    -- tunnl
  congressional_district_id   text references congressional_districts(id),
  -- TBD: all data columns after Tunnl data inspection
  raw                         jsonb,
  ingested_at                 timestamptz default now()
)

-- ─── WORKFORCE MOVEMENT ──────────────────────────────────────────────────────

workforce_movement (
  id                          uuid primary key default gen_random_uuid(),
  source                      text not null,    -- revelio
  congressional_district_id   text references congressional_districts(id),
  -- TBD: all data columns after Revelio data inspection
  raw                         jsonb,
  ingested_at                 timestamptz default now()
)

-- ─── VOTER FILE ──────────────────────────────────────────────────────────────

voter_file (
  id                                uuid primary key default gen_random_uuid(),
  source                            text not null,    -- L2, TargetSmart
  congressional_district_id         text references congressional_districts(id),
  state_leg_upper_district_id       text references state_leg_districts_upper(id),
  state_leg_lower_district_id       text references state_leg_districts_lower(id),
  precinct_id                       text references precincts(id),
  -- TBD: all data columns after vendor data inspection
  raw                               jsonb,
  ingested_at                       timestamptz default now()
)

voter_lists (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  created_by            uuid references profiles(id),
  name                  text not null,
  description           text,
  filter_criteria       jsonb not null,
  -- criteria used to build the list — applied against voter_file at export time
  record_count          integer,
  status                text default 'draft',
  -- statuses: draft, built, exported, archived
  built_at              timestamptz,
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
)

voter_list_exports (
  id                    uuid primary key default gen_random_uuid(),
  list_id               uuid references voter_lists(id),
  org_id                uuid references organizations(id),
  requested_by          uuid references profiles(id),
  format                text,
  -- formats: csv, json
  file_url              text,
  record_count          integer,
  created_at            timestamptz default now()
)

-- ─── POLLING ─────────────────────────────────────────────────────────────────

polling_waves (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  wave_name             text not null,
  wave_number           integer,
  wave_date             date,
  methodology           text,
  sample_size           integer,
  vendor                text,
  -- vendors: SSRS, Dynata
  margin_of_error       numeric,
  created_at            timestamptz default now()
)

polling_responses (
  id                    uuid primary key default gen_random_uuid(),
  wave_id               uuid references polling_waves(id),
  org_id                uuid references organizations(id),
  congressional_district_id   text references congressional_districts(id),
  state                 text,
  question_id           text,
  question_text         text,
  response_value        text,
  weight                numeric,
  demographic_data      jsonb,
  -- TBD: demographic variable columns on first wave data inspection
  ingested_at           timestamptz default now()
)

polling_toplines (
  id                    uuid primary key default gen_random_uuid(),
  wave_id               uuid references polling_waves(id),
  org_id                uuid references organizations(id),
  congressional_district_id   text references congressional_districts(id),
  question_id           text,
  question_text         text,
  response_value        text,
  pct                   numeric,
  n                     integer,
  margin_of_error       numeric,
  created_at            timestamptz default now()
)
```

---

## Section 5 — Phase 3 Data (Schema Now, Data Later)

All data columns TBD. Tables exist as placeholders. No columns added until data agreements are signed and real data is inspected.

```sql
consumer_intelligence (
  id                          uuid primary key default gen_random_uuid(),
  source                      text not null,    -- experian
  congressional_district_id   text references congressional_districts(id),
  -- TBD: all data columns after Experian ConsumerView contract and data inspection
  raw                         jsonb,
  ingested_at                 timestamptz default now()
)

labor_market (
  id                          uuid primary key default gen_random_uuid(),
  source                      text not null,    -- lightcast
  congressional_district_id   text references congressional_districts(id),
  -- TBD: all data columns after Lightcast contract and data inspection
  raw                         jsonb,
  ingested_at                 timestamptz default now()
)

health_utilization (
  id                          uuid primary key default gen_random_uuid(),
  source                      text not null,    -- symphony health
  congressional_district_id   text references congressional_districts(id),
  -- TBD: all data columns after Symphony Health contract and data inspection
  raw                         jsonb,
  ingested_at                 timestamptz default now()
)

cms_claims (
  id                          uuid primary key default gen_random_uuid(),
  source                      text not null,    -- CMS RESDAC
  congressional_district_id   text references congressional_districts(id),
  -- TBD: all data columns after RESDAC data use agreement approval and file inspection
  raw                         jsonb,
  ingested_at                 timestamptz default now()
)
```

---

## Section 6 — Platform Products

```sql
-- ─── STAKEHOLDER MAPPING ─────────────────────────────────────────────────────

stakeholders (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  name                  text not null,
  type                  text not null,
  -- types: legislator, regulator, organization, media, community, business, academic
  subtype               text,
  congressional_district_id   text references congressional_districts(id),
  state                 text,
  party                 text,
  title                 text,
  organization          text,
  email                 text,
  phone                 text,
  website               text,
  profile_data          jsonb,
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
)

stakeholder_scores (
  id                    uuid primary key default gen_random_uuid(),
  stakeholder_id        uuid references stakeholders(id),
  org_id                uuid references organizations(id),
  sentiment_score       numeric,
  -- -10 to 10
  influence_score       numeric,
  -- 0 to 10
  position              text,
  -- positions: strategic_partner, high_value_partner, valuable_partner,
  --            collaborate_with, cooperate, commit, connect,
  --            maintain, monitor, identify, respond_to,
  --            protect_brand, defend_against, actively_defend_against
  movement              text,
  -- movements: improving, stable, declining
  scored_at             timestamptz default now(),
  scored_by             text,
  -- scored_by: agent, manual, import
  notes                 text
)

stakeholder_tags (
  id                    uuid primary key default gen_random_uuid(),
  stakeholder_id        uuid references stakeholders(id),
  org_id                uuid references organizations(id),
  tag                   text not null,
  created_at            timestamptz default now()
)

stakeholder_interactions (
  id                    uuid primary key default gen_random_uuid(),
  stakeholder_id        uuid references stakeholders(id),
  org_id                uuid references organizations(id),
  user_id               uuid references profiles(id),
  interaction_type      text,
  -- types: meeting, call, email, event, testimony, media
  interaction_date      date,
  summary               text,
  sentiment_shift       numeric,
  created_at            timestamptz default now()
)

-- ─── SURVEY TOOL ─────────────────────────────────────────────────────────────

surveys (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  created_by            uuid references profiles(id),
  title                 text not null,
  description           text,
  slug                  text unique not null,
  status                text not null default 'draft',
  -- statuses: draft, active, paused, closed
  questions             jsonb not null,
  settings              jsonb default '{}',
  -- settings: require_zip, allow_anonymous, max_responses, close_date
  response_count        integer default 0,
  published_at          timestamptz,
  closed_at             timestamptz,
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
)

survey_responses (
  id                    uuid primary key default gen_random_uuid(),
  survey_id             uuid references surveys(id),
  org_id                uuid references organizations(id),
  zip_code              text not null,
  congressional_district_id         text references congressional_districts(id),
  state_leg_upper_district_id       text references state_leg_districts_upper(id),
  state_leg_lower_district_id       text references state_leg_districts_lower(id),
  state                 text,
  county                text,
  responses             jsonb not null,
  district_context      jsonb,
  -- enriched at submission: ACS, BLS, FEC, CDC, legislative context
  respondent_metadata   jsonb,
  -- browser, device, referrer — no PII
  submitted_at          timestamptz default now()
)

survey_exports (
  id                    uuid primary key default gen_random_uuid(),
  survey_id             uuid references surveys(id),
  org_id                uuid references organizations(id),
  requested_by          uuid references profiles(id),
  format                text,
  -- formats: csv, json, xlsx
  file_url              text,
  record_count          integer,
  created_at            timestamptz default now()
)

survey_templates (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  -- null for platform-level templates available to all clients
  created_by            uuid references profiles(id),
  name                  text not null,
  description           text,
  category              text,
  -- categories: workforce, healthcare, housing, policy, general
  questions             jsonb not null,
  is_public             boolean default false,
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
)

survey_versions (
  id                    uuid primary key default gen_random_uuid(),
  survey_id             uuid references surveys(id),
  org_id                uuid references organizations(id),
  version_number        integer not null,
  questions_snapshot    jsonb not null,
  settings_snapshot     jsonb,
  saved_by              uuid references profiles(id),
  created_at            timestamptz default now()
)

-- ─── CONSORTIUM SCORECARDS ───────────────────────────────────────────────────

scorecards (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  name                  text not null,
  description           text,
  geography_type        text,
  -- types: congressional_district, city, state, region
  status                text default 'draft',
  published_at          timestamptz,
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
)

scorecard_metrics (
  id                    uuid primary key default gen_random_uuid(),
  scorecard_id          uuid references scorecards(id),
  metric_name           text not null,
  metric_category       text,
  weight                numeric,
  data_source           text,
  created_at            timestamptz default now()
)

scorecard_results (
  id                    uuid primary key default gen_random_uuid(),
  scorecard_id          uuid references scorecards(id),
  congressional_district_id   text references congressional_districts(id),
  period_date           date,
  overall_score         numeric,
  metric_scores         jsonb,
  published_at          timestamptz,
  created_at            timestamptz default now()
)

-- ─── REPORTS AND OUTPUTS ─────────────────────────────────────────────────────

reports (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  created_by            uuid references profiles(id),
  title                 text not null,
  type                  text not null,
  -- types: district_brief, stakeholder_summary, survey_analysis, legislative_digest,
  --        sentiment_snapshot, voter_analysis, scorecard_summary
  status                text default 'draft',
  -- statuses: draft, generated, published, archived
  content               jsonb,
  -- structured report content
  file_url              text,
  -- if exported to PDF or other format
  data_snapshot         jsonb,
  -- snapshot of underlying data at time of generation
  generated_at          timestamptz,
  archived_at           timestamptz,
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
)

documents (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  uploaded_by           uuid references profiles(id),
  name                  text not null,
  type                  text,
  -- types: attachment, export, report, brief, testimony, memo
  file_url              text not null,
  file_size_bytes       integer,
  mime_type             text,
  related_resource_type text,
  related_resource_id   uuid,
  archived_at           timestamptz,
  created_at            timestamptz default now()
)

data_exports (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  requested_by          uuid references profiles(id),
  export_type           text not null,
  -- types: district_data, legislation, stakeholders, voter_list, survey_responses, full_lake
  filter_criteria       jsonb,
  format                text,
  -- formats: csv, json, xlsx
  status                text default 'pending',
  -- statuses: pending, processing, complete, failed
  file_url              text,
  record_count          integer,
  completed_at          timestamptz,
  created_at            timestamptz default now()
)

time_series_snapshots (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  snapshot_type         text not null,
  -- types: district_profile, stakeholder_score, sentiment_index, legislation_status
  resource_id           uuid,
  -- id of the thing being snapshotted
  congressional_district_id   text references congressional_districts(id),
  data                  jsonb not null,
  snapshotted_at        timestamptz default now()
)

client_data_access (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  dataset               text not null,
  -- dataset: legislation, fec, bls, acs, cdc, hud, crime, education, pew,
  --          voter_file, polling, consumer_intelligence, labor_market, health
  access_granted_at     timestamptz default now(),
  access_revoked_at     timestamptz,
  granted_by            uuid references profiles(id)
)

-- ─── PILL PRODUCTS — PAC INTELLIGENCE + INSTITUTE ────────────────────────────

pac_intelligence (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  congressional_district_id   text references congressional_districts(id),
  cycle                 integer,
  analysis_type         text,
  -- types: persuasion_targeting, issue_hardening, terrain_assessment
  findings              jsonb,
  created_by            uuid references profiles(id),
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
)

institute_publications (
  id                    uuid primary key default gen_random_uuid(),
  title                 text not null,
  type                  text not null,
  -- types: longitudinal_index, policy_brief, public_report, press_release
  issue_area            text,
  summary               text,
  content               jsonb,
  file_url              text,
  published_at          timestamptz,
  status                text default 'draft',
  -- statuses: draft, review, published, archived
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
)

-- ─── PILL PRODUCTS — GRASSROOTS CAMPAIGNS ────────────────────────────────────

grassroots_campaigns (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  created_by            uuid references profiles(id),
  name                  text not null,
  description           text,
  issue_area            text,
  target_districts      text[],
  -- array of congressional_district ids
  status                text default 'planning',
  -- statuses: planning, active, paused, complete, archived
  strategy              jsonb,
  started_at            date,
  ended_at              date,
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
)

grassroots_actions (
  id                    uuid primary key default gen_random_uuid(),
  campaign_id           uuid references grassroots_campaigns(id),
  org_id                uuid references organizations(id),
  action_type           text not null,
  -- types: email, call, event, petition, social, door_knock
  congressional_district_id   text references congressional_districts(id),
  target_count          integer,
  completed_count       integer,
  results               jsonb,
  action_date           date,
  created_at            timestamptz default now()
)

-- ─── ISSUE WATCHLISTS ────────────────────────────────────────────────────────

issue_watchlists (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  created_by            uuid references profiles(id),
  name                  text not null,
  issue_areas           text[],
  keywords              text[],
  target_districts      text[],
  alert_on_change       boolean default true,
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
)

-- ─── INTELLIGENCE OUTPUTS ────────────────────────────────────────────────────

district_briefs (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  congressional_district_id   text references congressional_districts(id),
  brief_text            text,
  data_snapshot         jsonb,
  -- snapshot of district data at time of brief
  generated_at          timestamptz default now(),
  generated_by          text default 'agent'
)

issue_alerts (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  issue_area            text not null,
  alert_type            text,
  -- types: legislation_moved, sentiment_shift, stakeholder_change
  congressional_district_id   text references congressional_districts(id),
  summary               text,
  severity              text,
  -- severities: low, medium, high, urgent
  source_record_id      uuid,
  source_record_type    text,
  acknowledged_at       timestamptz,
  acknowledged_by       uuid references profiles(id),
  created_at            timestamptz default now()
)

saved_searches (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  user_id               uuid references profiles(id),
  name                  text,
  search_type           text,
  -- types: legislation, stakeholder, district, sentiment
  parameters            jsonb,
  alert_on_change       boolean default false,
  last_run_at           timestamptz,
  created_at            timestamptz default now()
)
```

---

## Section 7 — MCP Server and Agent Infrastructure

```sql
mcp_tools (
  id                    uuid primary key default gen_random_uuid(),
  name                  text unique not null,
  description           text,
  input_schema          jsonb,
  version               text,
  active                boolean default true,
  created_at            timestamptz default now()
)

mcp_queries (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  user_id               uuid references profiles(id),
  tool_name             text not null,
  input_params          jsonb,
  result_summary        text,
  result_record_count   integer,
  status                text,
  -- statuses: success, error, timeout
  duration_ms           integer,
  error_message         text,
  created_at            timestamptz default now()
)

agents (
  id                    uuid primary key default gen_random_uuid(),
  name                  text unique not null,
  description           text,
  workflow_definition   jsonb,
  version               text,
  active                boolean default true,
  created_at            timestamptz default now()
)

agent_runs (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  user_id               uuid references profiles(id),
  agent_id              uuid references agents(id),
  agent_name            text not null,
  input                 jsonb,
  output                jsonb,
  tool_calls            jsonb,
  -- array of tool calls made during run
  status                text,
  -- statuses: running, success, error, partial
  tokens_used           integer,
  duration_ms           integer,
  error_message         text,
  created_at            timestamptz default now()
)
```

---

## Section 8 — Ingestion Infrastructure

```sql
ingestion_runs (
  id                    uuid primary key default gen_random_uuid(),
  source                text not null,
  run_type              text,
  -- types: full, incremental, backfill
  status                text,
  -- statuses: running, success, error, partial
  records_processed     integer default 0,
  records_inserted      integer default 0,
  records_updated       integer default 0,
  records_failed        integer default 0,
  error_log             jsonb,
  started_at            timestamptz default now(),
  completed_at          timestamptz
)

ingestion_errors (
  id                    uuid primary key default gen_random_uuid(),
  run_id                uuid references ingestion_runs(id),
  source                text not null,
  record_id             text,
  error_type            text,
  error_message         text,
  raw_record            jsonb,
  created_at            timestamptz default now()
)
```

---

## Notes on This Schema

**Columns marked TBD** will be added when the actual data source is inspected and real column values are confirmed. Do not invent column names. Do not add columns until the data exists to populate them.

**The `raw` column** on every ingestion table preserves the original source record exactly as received. This is non-negotiable. If a column is later found to have been incorrectly parsed, the raw record allows reprocessing without re-fetching from the source.

**Row-level security policies** must be written for every table in Sections 1, 6, and 7 before any client data is written. Tables in Sections 3, 4, and 5 contain public data and do not require RLS.

**State legislative district tables** are included in the schema now. The `zip_to_district` table has placeholder columns for both chambers. The geometry tables are empty until Phase 2 geographic overlay work begins. Do not leave these out of the Supabase setup.

**Migrations** are required for any column added after initial setup. Name migrations descriptively: `add_poverty_rate_to_acs_demographics`, not `update_schema`. Every migration is documented in a `MIGRATIONS.md` file with the date, the reason, and the columns changed.
