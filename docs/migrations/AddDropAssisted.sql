BEGIN TRANSACTION;
IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260221210511_AddDropAssisted'
)
BEGIN
    ALTER TABLE [Drops] ADD [Assisted] bit NOT NULL DEFAULT CAST(0 AS bit);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260221210511_AddDropAssisted'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductValue])
    VALUES (N'20260221210511_AddDropAssisted', N'9.0.8');
END;

COMMIT;
GO
