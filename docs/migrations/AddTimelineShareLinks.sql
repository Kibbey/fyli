Build started...
Build succeeded.
BEGIN TRANSACTION;
IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260210222732_AddTimelineShareLinks'
)
BEGIN
    CREATE TABLE [TimelineShareLinks] (
        [TimelineShareLinkId] int NOT NULL IDENTITY,
        [TimelineId] int NOT NULL,
        [CreatorUserId] int NOT NULL,
        [Token] uniqueidentifier NOT NULL,
        [IsActive] bit NOT NULL,
        [CreatedAt] datetime2 NOT NULL,
        [ExpiresAt] datetime2 NULL,
        [ViewCount] int NOT NULL,
        CONSTRAINT [PK_TimelineShareLinks] PRIMARY KEY ([TimelineShareLinkId]),
        CONSTRAINT [FK_TimelineShareLinks_Timelines_TimelineId] FOREIGN KEY ([TimelineId]) REFERENCES [Timelines] ([TimelineId]) ON DELETE NO ACTION,
        CONSTRAINT [FK_TimelineShareLinks_UserProfiles_CreatorUserId] FOREIGN KEY ([CreatorUserId]) REFERENCES [UserProfiles] ([UserId]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260210222732_AddTimelineShareLinks'
)
BEGIN
    CREATE INDEX [IX_TimelineShareLinks_CreatorUserId] ON [TimelineShareLinks] ([CreatorUserId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260210222732_AddTimelineShareLinks'
)
BEGIN
    CREATE INDEX [IX_TimelineShareLinks_TimelineId] ON [TimelineShareLinks] ([TimelineId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260210222732_AddTimelineShareLinks'
)
BEGIN
    CREATE UNIQUE INDEX [IX_TimelineShareLinks_Token] ON [TimelineShareLinks] ([Token]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260210222732_AddTimelineShareLinks'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20260210222732_AddTimelineShareLinks', N'9.0.8');
END;

COMMIT;
GO


