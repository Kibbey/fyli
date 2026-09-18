-- Prod catch-up: indexes declared in 20210502004355_Initial that never landed
-- on the EF6-era production schema (PK_dbo.* names).
--
-- Not an EF migration. Do NOT insert into __EFMigrationsHistory.
-- Idempotent on sys.indexes. Each CREATE INDEX is its own statement so a
-- failure does not roll back indexes already built.
--
-- Prefer off-peak. These can lock the table for the duration of the build.
-- On Enterprise / Azure SQL, add WITH (ONLINE = ON) to each CREATE INDEX.

-- 1. UserDrops — OtherUsersDrops.Any(UserId) / join by DropId
--    Prod currently has only PK_dbo.UserDrop (UserDropId).
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    JOIN sys.tables t ON t.object_id = i.object_id
    WHERE t.name = N'UserDrops' AND i.name = N'IX_UserDrops_UserId'
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_UserDrops_UserId]
        ON [UserDrops] ([UserId]);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    JOIN sys.tables t ON t.object_id = i.object_id
    WHERE t.name = N'UserDrops' AND i.name = N'IX_UserDrops_DropId'
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_UserDrops_DropId]
        ON [UserDrops] ([DropId]);
END
GO

-- 2. NetworkDrops — TagDrops.Any from a drop
--    Unique IX_TagDrop_UserTagId_DropId leads with UserTagId, so DropId cannot seek.
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    JOIN sys.tables t ON t.object_id = i.object_id
    WHERE t.name = N'NetworkDrops' AND i.name = N'IX_NetworkDrops_DropId'
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_NetworkDrops_DropId]
        ON [NetworkDrops] ([DropId]);
END
GO

-- 3. Drops — owner branch of GetAllDrops (x.UserId == currentUser)
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    JOIN sys.tables t ON t.object_id = i.object_id
    WHERE t.name = N'Drops' AND i.name = N'IX_Drops_UserId'
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_Drops_UserId]
        ON [Drops] ([UserId]);
END
GO

-- 4. Nested MapDrops loads — prod ImageDrops/MovieDrops/Comments have no DropId index
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    JOIN sys.tables t ON t.object_id = i.object_id
    WHERE t.name = N'ImageDrops' AND i.name = N'IX_ImageDrops_DropId'
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_ImageDrops_DropId]
        ON [ImageDrops] ([DropId]);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    JOIN sys.tables t ON t.object_id = i.object_id
    WHERE t.name = N'MovieDrops' AND i.name = N'IX_MovieDrops_DropId'
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_MovieDrops_DropId]
        ON [MovieDrops] ([DropId]);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    JOIN sys.tables t ON t.object_id = i.object_id
    WHERE t.name = N'Comments' AND i.name = N'IX_Comments_DropId'
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_Comments_DropId]
        ON [Comments] ([DropId]);
END
GO

-- 5. Optional — reverse lookup "tags this user can see".
--    Nested EXISTS already seeks PK (UserTagId, UserId). Include to match Initial.
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    JOIN sys.tables t ON t.object_id = i.object_id
    WHERE t.name = N'NetworkViewers' AND i.name = N'IX_NetworkViewers_UserId'
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_NetworkViewers_UserId]
        ON [NetworkViewers] ([UserId]);
END
GO
