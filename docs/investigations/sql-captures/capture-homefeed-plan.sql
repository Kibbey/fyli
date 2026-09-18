-- Capture the execution plan for the 25s home-feed query.
-- Source: docs/investigations/sql-captures/2026-09-17-getdrops-homefeed-25s.sql
--
-- Run against PROD. Read-only (SELECT only, no writes).
--
-- EASIEST: open this in SSMS / Azure Data Studio, click "Include Actual Execution
-- Plan" (Ctrl+M), run, then look at the plan tab.
--
-- Otherwise the STATISTICS output below gives most of the answer in text form.
--
-- Nothing to edit: the script picks the user with the most memories on its own,
-- which is the worst case for the feed and the one most likely to reproduce 25s.
-- To test a specific user instead, replace the SELECT on the @userId line.

SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;

-- Heaviest user by memory count = worst case for the permission predicate.
DECLARE @userId int = (
    SELECT TOP 1 [UserId] FROM [Drops] GROUP BY [UserId] ORDER BY COUNT(*) DESC
);
DECLARE @p_1 int = 0;    -- skip
DECLARE @p_2 int = 15;   -- take (home feed page size)

PRINT 'Testing userId = ' + CAST(@userId AS varchar(20));

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- The permission + paging core of GetDrops. The full MapDrops projection is
-- omitted on purpose: this is the part that decides the plan shape.
SELECT [d].[DropId]
FROM [Drops] AS [d]
WHERE EXISTS (
        SELECT 1
        FROM [NetworkDrops] AS [n]
        INNER JOIN [UserNetworks] AS [u] ON [n].[UserTagId] = [u].[UserTagId]
        WHERE [d].[DropId] = [n].[DropId]
          AND EXISTS (
                SELECT 1 FROM [NetworkViewers] AS [n0]
                WHERE [u].[UserTagId] = [n0].[UserTagId] AND [n0].[UserId] = @userId))
   OR [d].[UserId] = @userId
   OR EXISTS (
        SELECT 1 FROM [UserDrops] AS [u0]
        WHERE [d].[DropId] = [u0].[DropId] AND [u0].[UserId] = @userId)
ORDER BY [d].[Created] DESC
OFFSET @p_1 ROWS FETCH NEXT @p_2 ROWS ONLY;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

-- WHAT TO LOOK FOR
--
-- STATISTICS TIME: is the time CPU time or elapsed time?
--   CPU time ~= elapsed  -> CPU-bound. The query is burning cycles. More RAM
--                           will not help; t3.medium will not help.
--   elapsed >> CPU time  -> waiting (IO or scheduler). Points at the instance.
--
-- STATISTICS IO: "logical reads" on Drops.
--   Huge logical reads on a ~1 GB database means the plan is re-reading pages
--   over and over -- the signature of a nested loop re-evaluating the EXISTS
--   per row. That is H1, and it is fixed in code, not with hardware.
--
-- PLAN: is there a Clustered Index Scan on Drops feeding a Sort?
--   Yes -> H1 confirmed. The permission OR cannot seek, so it scans and sorts
--          everything before OFFSET/FETCH keeps 15 rows.
