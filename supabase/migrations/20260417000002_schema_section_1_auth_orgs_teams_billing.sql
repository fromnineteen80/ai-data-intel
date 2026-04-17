-- SCHEMA.md Section 1 — Authentication, Organizations, Teams, Billing.
-- Deployed in BUILD.md Step 2 order: organizations, profiles, memberships/teams,
-- session/audit/notifications/prefs, subscriptions/billing, api/webhooks.
-- user_preferences.default_district is declared here without its FK; the FK to
-- congressional_districts(id) is added at the end of the Section 2 migration.

-- ─── 1. organizations ────────────────────────────────────────────────────────
create table organizations (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  slug            text unique not null,
  type            text,                 -- corporate, political, consulting, nonprofit, individual
  tier            text not null default 'base',    -- base, polling, full
  status          text not null default 'active',  -- trial, active, suspended, churned
  owner_id        uuid,                 -- FK to profiles added after profiles exists
  billing_email   text,
  domain          text,
  logo_url        text,
  settings        jsonb default '{}',
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);

-- ─── 2. profiles ─────────────────────────────────────────────────────────────
create table profiles (
  id                    uuid primary key references auth.users(id) on delete cascade,
  full_name             text,
  avatar_url            text,
  phone                 text,
  timezone              text default 'America/New_York',
  last_seen_at          timestamptz,
  onboarding_complete   boolean default false,
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
);

alter table organizations
  add constraint organizations_owner_id_fkey
  foreign key (owner_id) references profiles(id);

-- ─── 3. org_memberships, teams, team_memberships, invitations ────────────────
create table org_memberships (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid references organizations(id) on delete cascade,
  user_id     uuid references profiles(id) on delete cascade,
  role        text not null default 'viewer',  -- owner, admin, analyst, viewer, guest
  department  text,
  title       text,
  joined_at   timestamptz default now(),
  invited_by  uuid references profiles(id),
  created_at  timestamptz default now(),
  updated_at  timestamptz default now(),
  unique (org_id, user_id)
);

create table teams (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid references organizations(id) on delete cascade,
  created_by   uuid references profiles(id),
  name         text not null,
  description  text,
  function     text,        -- government_affairs, communications, marketing, legal,
                            -- policy, public_affairs, community_relations, digital,
                            -- sustainability, foundation, strategy, analytics,
                            -- political_action, executive
  data_focus   text[],
  settings     jsonb default '{}',
  created_at   timestamptz default now(),
  updated_at   timestamptz default now(),
  unique (org_id, name)
);

create table team_memberships (
  id          uuid primary key default gen_random_uuid(),
  team_id     uuid references teams(id) on delete cascade,
  user_id     uuid references profiles(id) on delete cascade,
  org_id      uuid references organizations(id),  -- denormalized for RLS
  role        text not null default 'member',     -- lead, member
  added_by    uuid references profiles(id),
  created_at  timestamptz default now(),
  unique (team_id, user_id)
);

create table invitations (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid references organizations(id) on delete cascade,
  invited_by   uuid references profiles(id),
  email        text not null,
  org_role     text not null default 'viewer',
  team_ids     uuid[],
  token        text unique not null,
  accepted_at  timestamptz,
  expires_at   timestamptz not null,
  created_at   timestamptz default now()
);

-- ─── 4. sessions, audit_log, notifications, user_preferences ─────────────────
create table sessions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references profiles(id),
  org_id       uuid references organizations(id),
  ip_address   inet,
  user_agent   text,
  started_at   timestamptz default now(),
  ended_at     timestamptz,
  created_at   timestamptz default now()
);

create table audit_log (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid references organizations(id),
  team_id        uuid references teams(id),
  user_id        uuid references profiles(id),
  action         text not null,   -- login, logout, create, update, delete, export,
                                  -- query, invite, remove_member
  resource_type  text,
  resource_id    uuid,
  metadata       jsonb,
  ip_address     inet,
  created_at     timestamptz default now()
);

create table notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references profiles(id),
  org_id      uuid references organizations(id),
  team_id     uuid references teams(id),
  type        text not null,
  title       text not null,
  body        text,
  read_at     timestamptz,
  action_url  text,
  created_at  timestamptz default now()
);

create table user_preferences (
  id                   uuid primary key references auth.users(id) on delete cascade,
  email_notifications  boolean default true,
  digest_frequency     text default 'weekly',  -- realtime, daily, weekly, never
  default_district     text,
  -- FK to congressional_districts(id) added in the Section 2 migration
  ui_settings          jsonb default '{}',
  updated_at           timestamptz default now()
);

-- ─── 5. subscriptions, add_ons, invoices, payment_methods, usage_events ──────
create table subscriptions (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid references organizations(id),
  tier                  text not null,                     -- base, polling, full
  status                text not null,                     -- trialing, active, past_due, canceled
  billing_interval      text not null default 'monthly',
  amount_cents          integer,
  currency              text default 'usd',
  current_period_start  date,
  current_period_end    date,
  canceled_at           timestamptz,
  external_id           text,
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
);

create table add_ons (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid references organizations(id),
  subscription_id  uuid references subscriptions(id),
  type             text not null,
  -- mcp_server, grassroots_campaign, consortium_scorecard,
  -- stakeholder_management, survey_tool
  status           text not null default 'active',
  amount_cents     integer,
  started_at       date,
  ended_at         date,
  created_at       timestamptz default now()
);

create table invoices (
  id                 uuid primary key default gen_random_uuid(),
  org_id             uuid references organizations(id),
  subscription_id    uuid references subscriptions(id),
  external_id        text,
  status             text not null,  -- draft, open, paid, void, uncollectible
  amount_cents       integer,
  amount_paid_cents  integer,
  currency           text default 'usd',
  period_start       date,
  period_end         date,
  due_date           date,
  paid_at            timestamptz,
  invoice_url        text,
  created_at         timestamptz default now()
);

create table payment_methods (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid references organizations(id),
  external_id  text,
  type         text,             -- card, ach, wire
  is_default   boolean default false,
  last_four    text,
  brand        text,
  expires_at   date,
  created_at   timestamptz default now()
);

create table usage_events (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid references organizations(id),
  team_id      uuid references teams(id),
  user_id      uuid references profiles(id),
  event_type   text not null,
  -- api_query, agent_run, survey_response, export, mcp_query
  quantity     integer default 1,
  metadata     jsonb,
  recorded_at  timestamptz default now()
);

-- ─── 6. api_keys, webhooks, webhook_deliveries ───────────────────────────────
create table api_keys (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid references organizations(id),
  created_by    uuid references profiles(id),
  name          text not null,
  key_hash      text not null,   -- hash only, never plaintext
  scopes        text[],
  -- read:districts, read:stakeholders, read:surveys, write:surveys, mcp:query
  last_used_at  timestamptz,
  expires_at    timestamptz,
  revoked_at    timestamptz,
  created_at    timestamptz default now()
);

create table webhooks (
  id                 uuid primary key default gen_random_uuid(),
  org_id             uuid references organizations(id),
  url                text not null,
  events             text[],
  -- survey.response, alert.created, stakeholder.scored, legislation.updated
  secret_hash        text not null,
  active             boolean default true,
  last_triggered_at  timestamptz,
  created_at         timestamptz default now()
);

create table webhook_deliveries (
  id             uuid primary key default gen_random_uuid(),
  webhook_id     uuid references webhooks(id),
  event_type     text not null,
  payload        jsonb,
  status_code    integer,
  response_body  text,
  delivered_at   timestamptz,
  created_at     timestamptz default now()
);

-- ─── Indexes required by RLS filters and common joins ────────────────────────
create index org_memberships_user_id_idx      on org_memberships(user_id);
create index org_memberships_org_id_idx       on org_memberships(org_id);
create index team_memberships_user_id_idx     on team_memberships(user_id);
create index team_memberships_org_id_idx      on team_memberships(org_id);
create index teams_org_id_idx                 on teams(org_id);
create index invitations_org_id_idx           on invitations(org_id);
create index sessions_user_id_idx             on sessions(user_id);
create index audit_log_org_id_idx             on audit_log(org_id);
create index notifications_user_id_idx        on notifications(user_id);
create index subscriptions_org_id_idx         on subscriptions(org_id);
create index add_ons_org_id_idx               on add_ons(org_id);
create index invoices_org_id_idx              on invoices(org_id);
create index payment_methods_org_id_idx       on payment_methods(org_id);
create index usage_events_org_id_idx          on usage_events(org_id);
create index api_keys_org_id_idx              on api_keys(org_id);
create index webhooks_org_id_idx              on webhooks(org_id);
create index webhook_deliveries_webhook_id_idx on webhook_deliveries(webhook_id);
