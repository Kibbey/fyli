BEGIN TRANSACTION;
IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260219192308_AddCacheEntry'
)
BEGIN
    CREATE TABLE [CacheEntries] (
        [CacheEntryId] int NOT NULL IDENTITY,
        [CacheKey] nvarchar(256) NOT NULL,
        [Value] nvarchar(max) NOT NULL,
        [ExpiresAt] datetime2 NOT NULL,
        [CreatedAt] datetime2 NOT NULL DEFAULT (GETUTCDATE()),
        CONSTRAINT [PK_CacheEntries] PRIMARY KEY ([CacheEntryId])
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260219192308_AddCacheEntry'
)
BEGIN
    CREATE INDEX [IX_CacheEntries_CacheKey] ON [CacheEntries] ([CacheKey]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260219192308_AddCacheEntry'
)
BEGIN
    CREATE INDEX [IX_CacheEntries_ExpiresAt] ON [CacheEntries] ([ExpiresAt]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260219192308_AddCacheEntry'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20260219192308_AddCacheEntry', N'9.0.8');
END;

COMMIT;
GO
