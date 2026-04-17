-- BUILD.md Step 1 — enable required Postgres extensions.
-- PostGIS: geometry columns in Section 2 (geographic reference).
-- uuid-ossp: explicit UUID generation functions; SCHEMA.md also uses gen_random_uuid()
--            which is available in PG 13+ without an extension.

create extension if not exists postgis;
create extension if not exists "uuid-ossp";
