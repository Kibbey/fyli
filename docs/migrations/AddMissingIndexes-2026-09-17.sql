-- ============================================================================
-- Prod catch-up #2: indexes declared in the EF model that never landed on the
-- EF6-era production schema.
--
-- Found by docs/migrations/IndexDriftAudit.sql on 2026-09-17: 9 of 75 declared
-- indexes missing. (Catch-up #1, AddMissingGetTimelineIndexes.sql, fixed 7 on
-- the GetTimeline path only.)
--
-- Not an EF migration. Do NOT insert into __EFMigrationsHistory.
-- Idempotent on sys.indexes. Each CREATE INDEX is its own batch so a failure
-- does not roll back indexes already built.
--
-- CREATE INDEX LOCKS THE TABLE while it builds. Run off-peak. On Enterprise /
-- Azure SQL add WITH (ONLINE = ON) to each statement.
--
-- Creates ALL 9 in one run. The tier comments are ordering only, not stop
-- points: they run safest-and-highest-value first, so if the window is cut
-- short the most valuable indexes already exist. Drops (largest table) is last.
-- ============================================================================

SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;

-- ---------------------------------------------------------------------------
-- TIER 1 - directly on a measured 18.9s production query. Do this one first.
--
-- 2026-09-17-timelines-19s.sql joins TimelineUsers on TimelineId twice:
--     LEFT JOIN [TimelineUsers] [t1] ON [t].[TimelineId] = [t1].[TimelineId]
--     EXISTS (... WHERE [t].[TimelineId] = [t0].[TimelineId] ...)
-- Neither can seek today. TimelineUsers PK leads with UserId, so TimelineId
-- lookups scan. This is a confirmed cause, not a guess.
-- ---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes i JOIN sys.tables t ON t.object_id = i.object_id
               WHERE t.name = N'TimelineUsers' AND i.name = N'IX_TimelineUsers_TimelineId')
BEGIN
    CREATE NONCLUSTERED INDEX [IX_TimelineUsers_TimelineId] ON [TimelineUsers] ([TimelineId]);
END
GO

-- ---------------------------------------------------------------------------
-- TIER 2 - notification lookups. Not measured slow, but SharedDropNotifications
-- is read on common paths and has NO secondary indexes at all today.
-- ---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes i JOIN sys.tables t ON t.object_id = i.object_id
               WHERE t.name = N'SharedDropNotifications' AND i.name = N'IX_SharedDropNotifications_TargetUserId')
BEGIN
    CREATE NONCLUSTERED INDEX [IX_SharedDropNotifications_TargetUserId] ON [SharedDropNotifications] ([TargetUserId]);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes i JOIN sys.tables t ON t.object_id = i.object_id
               WHERE t.name = N'SharedDropNotifications' AND i.name = N'IX_SharedDropNotifications_DropId')
BEGIN
    CREATE NONCLUSTERED INDEX [IX_SharedDropNotifications_DropId] ON [SharedDropNotifications] ([DropId]);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes i JOIN sys.tables t ON t.object_id = i.object_id
               WHERE t.name = N'SharedDropNotifications' AND i.name = N'IX_SharedDropNotifications_SharerUserId')
BEGIN
    CREATE NONCLUSTERED INDEX [IX_SharedDropNotifications_SharerUserId] ON [SharedDropNotifications] ([SharerUserId]);
END
GO

-- ---------------------------------------------------------------------------
-- TIER 3 - moderate. Comments already got IX_Comments_DropId in catch-up #1;
-- UserId supports "comments by this user". ShareRequests backs connection
-- requests (lower traffic than the feed).
-- ---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes i JOIN sys.tables t ON t.object_id = i.object_id
               WHERE t.name = N'Comments' AND i.name = N'IX_Comments_UserId')
BEGIN
    CREATE NONCLUSTERED INDEX [IX_Comments_UserId] ON [Comments] ([UserId]);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes i JOIN sys.tables t ON t.object_id = i.object_id
               WHERE t.name = N'ShareRequests' AND i.name = N'IX_ShareRequests_TargetsUserId')
BEGIN
    CREATE NONCLUSTERED INDEX [IX_ShareRequests_TargetsUserId] ON [ShareRequests] ([TargetsUserId]);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes i JOIN sys.tables t ON t.object_id = i.object_id
               WHERE t.name = N'ShareRequests' AND i.name = N'IX_ShareRequests_RequesterUserId')
BEGIN
    CREATE NONCLUSTERED INDEX [IX_ShareRequests_RequesterUserId] ON [ShareRequests] ([RequesterUserId]);
END
GO

-- ---------------------------------------------------------------------------
-- TIER 4 - low value, and the Drops one carries the most lock risk.
--
-- Drops is the largest table in the schema. CompletedByUserId is used only by
-- the "completed by" lookup, which is not on any hot path. Build it LAST, in
-- its own window, and skip it entirely if the maintenance window is tight.
-- ---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes i JOIN sys.tables t ON t.object_id = i.object_id
               WHERE t.name = N'UserEmails' AND i.name = N'IX_UserEmails_UserId')
BEGIN
    CREATE NONCLUSTERED INDEX [IX_UserEmails_UserId] ON [UserEmails] ([UserId]);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes i JOIN sys.tables t ON t.object_id = i.object_id
               WHERE t.name = N'Drops' AND i.name = N'IX_Drops_CompletedByUserId')
BEGIN
    CREATE NONCLUSTERED INDEX [IX_Drops_CompletedByUserId] ON [Drops] ([CompletedByUserId]);
END
GO

-- Re-run docs/migrations/IndexDriftAudit.sql afterwards. Expect 75 / 0.
