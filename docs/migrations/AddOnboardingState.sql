BEGIN TRANSACTION;
IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260301034947_AddOnboardingState'
)
BEGIN
    ALTER TABLE [UserProfiles] ADD [OnboardingState] varchar(1000) NULL;
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260301034947_AddOnboardingState'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20260301034947_AddOnboardingState', N'9.0.8');
END;

COMMIT;
GO
