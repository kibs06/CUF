# Supabase Migrations

## Naming rule (CI-enforced)

Migration filenames must be `<14-digit-timestamp>_description.sql` —
**no letter suffixes, no missing timestamps**. Examples:

- ✅ `20260715090100_fix_fk_join_syntax.sql`
- ❌ `20260715a_fix_fk_join_syntax.sql` (letter suffix)
- ❌ `messaging_attachments_schema.sql` (no timestamp)

The Supabase CLI skips any file that doesn't match `^<digits>_name.sql$`,
which silently breaks the migration chain (a skipped migration's tables
are missing for every later migration). CI (`supabase-migrations.yml`)
runs `supabase db reset` from scratch and will fail loudly on this.

## Ordering

Migrations apply in lexicographic (filename) order. Any migration that
references a table or column must be timestamped **strictly after** the
migration that creates it. If two files are created on the same day, give
them full 14-digit timestamps (`YYYYMMDDHHMMSS`) so ordering is explicit.

## Base schema

`20260601000000_base_schema.sql` is the frozen pre-migration baseline
(the state of the database when the first real migration,
`20260702_notifications.sql`, was written). It exists because
`supabase/schema.sql` is a **reference-only snapshot** that the CLI does
**not** apply to fresh databases — without it, `db reset` fails with
`relation "public.profiles" does not exist`.

Do not edit it to add new objects — add a new migration instead. Note it
uses **UUID** for `products.id`, `orders.id` and `order_items.id` to match
the live database (see the header comment inside the file for why).
