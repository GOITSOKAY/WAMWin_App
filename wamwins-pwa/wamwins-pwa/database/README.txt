WAMWins database (PostgreSQL 15+)
Install on an empty database, in this order, stopping on the first error:
  psql -v ON_ERROR_STOP=1 -d <db> -f 01_schema.sql -f 02_seed_reference.sql -f 04_profiling.sql -f 06_age_rules.sql \
       -f 08_kitchen_catalog.sql -f 09_kitchen_catalog_seed.sql -f 10_kitchen_cutover.sql -f 12_about_you.sql -f 13_comments.sql
Tests (03, 05, 07, 11, 14) create sample data and roll it back. Run them on a scratch database only.
Full reference: WAMWins_Database_Documentation.pdf

SUPABASE + WAMWins APP (added)
After the files above, run on Supabase:
  15_supabase.sql      connects core.uid() to Supabase Auth, roles, auth.users -> core.users, API schemas, app columns
  16_app_catalog.sql   foods, aliases, allergens and recipes with the codes the app uses (generated from the app)
Then follow ../README.md (Connect to Supabase).
