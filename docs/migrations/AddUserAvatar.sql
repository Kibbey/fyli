-- AddUserAvatar (20260920135329)
--
-- Adds three nullable avatar columns to [UserProfiles] plus a filtered unique
-- index on [AvatarToken].
--
-- WHY
-- One optional photo per user, keyed by an unguessable GUID rather than a user
-- id so the anonymous read endpoint (share-link visitors must see faces) is not
-- an enumeration surface. The token rotates on every upload, which doubles as
-- cache busting.
--
-- The index is UNIQUE and FILTERED: the anonymous endpoint looks a user up by
-- token on every uncached request, and the filter keeps the many NULLs (every
-- user without a photo) out of the uniqueness constraint.
--
-- BEFORE RUNNING
-- Run this BEFORE deploying the application. Once the app build ships, every EF
-- query against [UserProfiles] names these columns in its SELECT -- login,
-- GetUser, GetConnections, and every feed projection -- so deploying first
-- produces "Invalid column name 'AvatarToken'" on essentially every request,
-- including all memory access. Running the script early is safe: the columns
-- are nullable and the currently-deployed build ignores them.
--
-- A filtered index (CREATE INDEX ... WHERE) requires QUOTED_IDENTIFIER and
-- ANSI_NULLS ON in the creating session. SET options are connection-level and
-- persist across GO batches, so setting them once here covers the whole script.
--
-- Production history table is EF6 [__MigrationHistory], not EF Core
-- [__EFMigrationsHistory]. Column adds are gated on COL_LENGTH and the index on
-- sys.indexes so this still works if history columns differ -- or if the
-- history table is absent entirely.
--
-- Safe to re-run.

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF COL_LENGTH(N'UserProfiles', N'AvatarToken') IS NULL
BEGIN
    ALTER TABLE [UserProfiles] ADD [AvatarToken] uniqueidentifier NULL;
END
GO

IF COL_LENGTH(N'UserProfiles', N'AvatarUpdatedAt') IS NULL
BEGIN
    ALTER TABLE [UserProfiles] ADD [AvatarUpdatedAt] datetime2 NULL;
END
GO

IF COL_LENGTH(N'UserProfiles', N'PendingAvatarSourceUrl') IS NULL
BEGIN
    ALTER TABLE [UserProfiles] ADD [PendingAvatarSourceUrl] varchar(1000) NULL;
END
GO

-- Separate batch: SQL Server cannot reference a column added earlier in the
-- same batch, and this index references [AvatarToken].
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_UserProfiles_AvatarToken'
      AND object_id = OBJECT_ID(N'[UserProfiles]')
)
BEGIN
    CREATE UNIQUE INDEX [IX_UserProfiles_AvatarToken]
        ON [UserProfiles] ([AvatarToken])
        WHERE [AvatarToken] IS NOT NULL;
END
GO

-- Wrapped in EXEC so [__MigrationHistory] is compiled only when it exists.
-- A bare reference fails to compile (Msg 208) even behind an OBJECT_ID guard,
-- because compilation precedes the runtime check.
IF OBJECT_ID(N'[__MigrationHistory]', N'U') IS NOT NULL
BEGIN
    IF COL_LENGTH(N'__MigrationHistory', N'ContextKey') IS NOT NULL
        EXEC(N'
            IF NOT EXISTS (SELECT 1 FROM [__MigrationHistory]
                           WHERE [MigrationId] LIKE N''%AddUserAvatar'')
                INSERT INTO [__MigrationHistory]
                    ([MigrationId], [ContextKey], [Model], [ProductVersion])
                VALUES (N''20260920135329_AddUserAvatar'',
                    N''Domain.Entities.StreamContext'', 0x, N''9.0.8'');');
    ELSE
        EXEC(N'
            IF NOT EXISTS (SELECT 1 FROM [__MigrationHistory]
                           WHERE [MigrationId] LIKE N''%AddUserAvatar'')
                INSERT INTO [__MigrationHistory] ([MigrationId], [ProductVersion])
                VALUES (N''20260920135329_AddUserAvatar'', N''9.0.8'');');
END
GO
