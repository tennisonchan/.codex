# TestEntityFactory Drizzle notes (Nov 2025)

- The factory now uses Drizzle (`src/db/drizzle`) for all inserts/reads; legacy `pooledSupabaseClient` is gone. Add new seeds with typed `db.insert(...)` + schema tables.
- Timestamps stored as strings (ISO) in Drizzle schema with `mode: 'string'`; convert `Date` via `.toISOString()` when seeding.
- Cleanup runs raw SQL deletes via `deleteEntity(tableName, id)`; ensure `registerEntity` uses the actual table name (e.g., `chart_of_accounts`, `auth.users`) so cleanup works and FK order stays correct.
- When adding factory methods, prefer existing repositories/services for domain logic (bills, expenses, etc.) and only touch Drizzle tables directly for simple seeds.
- Tests that rely on the factory should continue to call `cleanUp()`/`tearDown()`; connection closing is now a no-op to avoid killing the shared Drizzle client.
