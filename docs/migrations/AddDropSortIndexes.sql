-- AddDropSortIndexes (20260918032350)
--
-- Adds IX_Drop_Created and IX_Drop_Date on [Drops].
--
-- WHY
-- Production sessions were sitting in RESOURCE_SEMAPHORE waits (~21.8s, 21.8s,
-- 24.3s, suspended) -- queueing for a query memory grant before execution even
-- begins. That is the ~25 second constant seen across unrelated queries, and it
-- is why the union rewrite (533x fewer logical reads) changed nothing: the wait
-- happens before the query runs, so query cost is irrelevant to it.
--
-- Memory grants are driven mainly by Sort and Hash operators. The feeds sort on
-- columns with no index:
--     home feed  ORDER BY [Created] DESC   (chronological: false)
--     storyline  ORDER BY [Date]           (chronological: true)
-- so every page requested a grant large enough to sort the whole visible set.
-- Indexing the sort columns removes the Sort operator and most of the grant.
--
-- SQL Server can scan an ascending index backwards, so a single ascending index
-- serves ORDER BY ... DESC. No descending index is needed.
--
-- See docs/investigations/2026-09-09-gettimeline-sql-timeout.md, Round 7.
--
-- BEFORE RUNNING
-- [Drops] is the largest table in the schema. CREATE INDEX locks it while it
-- builds. Run off-peak. On Enterprise / Azure SQL add WITH (ONLINE = ON) to
-- each CREATE INDEX.
--
-- Production history table is EF6 [__MigrationHistory], not EF Core
-- [__EFMigrationsHistory]. Index create is gated on sys.indexes so it still
-- works if history columns differ.

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_Drop_Created'
      AND object_id = OBJECT_ID(N'[Drops]')
)
BEGIN
    CREATE INDEX [IX_Drop_Created] ON [Drops] ([Created]);
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_Drop_Date'
      AND object_id = OBJECT_ID(N'[Drops]')
)
BEGIN
    CREATE INDEX [IX_Drop_Date] ON [Drops] ([Date]);
END
GO

IF OBJECT_ID(N'[__MigrationHistory]', N'U') IS NOT NULL
AND NOT EXISTS (
    SELECT 1 FROM [__MigrationHistory]
    WHERE [MigrationId] = N'20260918032350_AddDropSortIndexes'
)
BEGIN
    IF COL_LENGTH(N'__MigrationHistory', N'ContextKey') IS NOT NULL
        INSERT INTO [__MigrationHistory] ([MigrationId], [ContextKey], [Model], [ProductVersion])
        VALUES (N'20260918032350_AddDropSortIndexes', N'Domain.Entities.StreamContext', 0x, N'9.0.8');
    ELSE
        INSERT INTO [__MigrationHistory] ([MigrationId], [ProductVersion])
        VALUES (N'20260918032350_AddDropSortIndexes', N'9.0.8');
END
GO
