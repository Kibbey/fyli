-- AddUserAvatar. Safe to re-run.
-- Filtered index (CREATE INDEX ... WHERE) requires these SET options in the
-- creating session; add them unconditionally rather than relying on the tool.
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

BEGIN TRANSACTION;
IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260920135329_AddUserAvatar'
)
BEGIN
    ALTER TABLE [UserProfiles] ADD [AvatarToken] uniqueidentifier NULL;
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260920135329_AddUserAvatar'
)
BEGIN
    ALTER TABLE [UserProfiles] ADD [AvatarUpdatedAt] datetime2 NULL;
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260920135329_AddUserAvatar'
)
BEGIN
    ALTER TABLE [UserProfiles] ADD [PendingAvatarSourceUrl] varchar(1000) NULL;
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260920135329_AddUserAvatar'
)
BEGIN
    EXEC(N'CREATE UNIQUE INDEX [IX_UserProfiles_AvatarToken] ON [UserProfiles] ([AvatarToken]) WHERE [AvatarToken] IS NOT NULL');
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260920135329_AddUserAvatar'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20260920135329_AddUserAvatar', N'9.0.8');
END;

COMMIT;
GO

