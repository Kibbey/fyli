-- AddStagedUpload (20260922122523)
--
-- Creates [StagedUploads]: one row per file staged before a memory exists.
--
-- WHY
-- Media S3 keys are derived from dropId, so nothing can upload until Save
-- creates the drop. A token-keyed staging row breaks that dependency, letting
-- bytes move while the parent types. Claimed at save; unclaimed rows and their
-- S3 objects are reaped by the lifecycle rule on the staging prefix.
--
-- [ClaimedDropId] is deliberately NOT a foreign key: a staging row must never
-- be able to block or cascade a drop delete.
--
-- BEFORE RUNNING
-- Run this BEFORE deploying the application. Deploy order is migration first,
-- application second -- never the reverse. Running early is safe: nothing in the
-- currently-deployed build reads this table.
--
-- The unclaimed index is filtered (CREATE INDEX ... WHERE), which requires
-- QUOTED_IDENTIFIER and ANSI_NULLS ON in the creating session. SET options are
-- connection-level and persist across GO, so setting them once covers the file.
--
-- Production history table is EF6 [__MigrationHistory], not EF Core
-- [__EFMigrationsHistory]. The history insert is wrapped in EXEC so it compiles
-- only where the table exists.
--
-- Safe to re-run.

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID(N'[StagedUploads]', N'U') IS NULL
BEGIN
    CREATE TABLE [StagedUploads] (
        [StagedUploadId] INT IDENTITY(1,1) NOT NULL,
        [UserId]         INT NOT NULL,
        [Token]          UNIQUEIDENTIFIER NOT NULL,
        [S3Key]          VARCHAR(400) NOT NULL,
        [Kind]           VARCHAR(10) NOT NULL,
        [ContentType]    VARCHAR(100) NOT NULL,
        [FileSize]       BIGINT NOT NULL,
        [CreatedAt]      DATETIME2 NOT NULL,
        [UploadedAt]     DATETIME2 NULL,
        [ClaimedAt]      DATETIME2 NULL,
        [ClaimedDropId]  INT NULL,
        [ClaimedMediaId] INT NULL,
        CONSTRAINT [PK_StagedUploads] PRIMARY KEY ([StagedUploadId]),
        CONSTRAINT [FK_StagedUploads_UserProfiles_UserId]
            FOREIGN KEY ([UserId]) REFERENCES [UserProfiles] ([UserId])
            ON DELETE NO ACTION
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_StagedUploads_Token'
      AND object_id = OBJECT_ID(N'[StagedUploads]')
)
BEGIN
    CREATE UNIQUE INDEX [IX_StagedUploads_Token]
        ON [StagedUploads] ([Token]);
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_StagedUploads_UserId_CreatedAt'
      AND object_id = OBJECT_ID(N'[StagedUploads]')
)
BEGIN
    CREATE INDEX [IX_StagedUploads_UserId_CreatedAt]
        ON [StagedUploads] ([UserId], [CreatedAt]);
END
GO

-- Ops: unclaimed rows older than the lifecycle window should be zero.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_StagedUploads_Unclaimed'
      AND object_id = OBJECT_ID(N'[StagedUploads]')
)
BEGIN
    CREATE INDEX [IX_StagedUploads_Unclaimed]
        ON [StagedUploads] ([CreatedAt])
        WHERE [ClaimedDropId] IS NULL;
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
                           WHERE [MigrationId] LIKE N''%AddStagedUpload'')
                INSERT INTO [__MigrationHistory]
                    ([MigrationId], [ContextKey], [Model], [ProductVersion])
                VALUES (N''20260922122523_AddStagedUpload'',
                    N''Domain.Entities.StreamContext'', 0x, N''9.0.8'');');
    ELSE
        EXEC(N'
            IF NOT EXISTS (SELECT 1 FROM [__MigrationHistory]
                           WHERE [MigrationId] LIKE N''%AddStagedUpload'')
                INSERT INTO [__MigrationHistory] ([MigrationId], [ProductVersion])
                VALUES (N''20260922122523_AddStagedUpload'', N''9.0.8'');');
END
GO
