# Ledger journal entries no longer store period_id

- Migration `20251105193450_remove_period_id_from_gl_journal_entries.sql` dropped `period_id` and related trigger/constraint; table now relies on `entry_date` only.
- Custom ledger schema (`src/db/ledger-schema.ts`) and `ledger-service` must omit `periodId` to match the Supabase schema; inserting with that column fails with `column "period_id" does not exist`.
- Fiscal period validation is no longer performed during journal entry create/update; callers should ensure date validity at a higher layer if needed.
- Verified on 2025-11-22 by running `pnpm test src/tests/ledger/ledger.integration.test.ts -t "allows duplicate line numbers on a single journal entry"` after removing the column usage.
