-- AddAsk. Safe to re-run.
-- Production history table is EF6 [__MigrationHistory], not EF Core [__EFMigrationsHistory].

IF OBJECT_ID(N'[Asks]', N'U') IS NULL
BEGIN
    CREATE TABLE [Asks] (
        [AskId] INT IDENTITY(1,1) NOT NULL,
        [UserId] INT NOT NULL,
        [Type] VARCHAR(16) NOT NULL,
        [Message] NVARCHAR(2000) NOT NULL,
        [Created] DATETIME2 NOT NULL,
        [Source] VARCHAR(32) NOT NULL,
        CONSTRAINT [PK_Asks] PRIMARY KEY ([AskId]),
        CONSTRAINT [FK_Asks_UserProfiles_UserId]
            FOREIGN KEY ([UserId]) REFERENCES [UserProfiles] ([UserId]) ON DELETE NO ACTION
    );
    CREATE INDEX [IX_Asks_Created] ON [Asks] ([Created]);
    CREATE INDEX [IX_Asks_UserId] ON [Asks] ([UserId]);
END
GO

IF OBJECT_ID(N'[__MigrationHistory]', N'U') IS NOT NULL
AND NOT EXISTS (
    SELECT 1 FROM [__MigrationHistory]
    WHERE [MigrationId] = N'20260918015900_AddAsk'
)
BEGIN
    IF COL_LENGTH(N'__MigrationHistory', N'ContextKey') IS NOT NULL
        INSERT INTO [__MigrationHistory] ([MigrationId], [ContextKey], [Model], [ProductVersion])
        VALUES (N'20260918015900_AddAsk', N'Domain.Entities.StreamContext', 0x, N'9.0.8');
    ELSE
        INSERT INTO [__MigrationHistory] ([MigrationId], [ProductVersion])
        VALUES (N'20260918015900_AddAsk', N'9.0.8');
END
GO
