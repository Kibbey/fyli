-- AddAppVisit. Safe to re-run.
-- Production history table is EF6 [__MigrationHistory], not EF Core [__EFMigrationsHistory].

IF OBJECT_ID(N'[AppVisits]', N'U') IS NULL
BEGIN
    CREATE TABLE [AppVisits] (
        [AppVisitId] INT IDENTITY(1,1) NOT NULL,
        [UserId] INT NOT NULL,
        [Path] VARCHAR(200) NOT NULL,
        [Created] DATETIME2 NOT NULL,
        CONSTRAINT [PK_AppVisits] PRIMARY KEY ([AppVisitId]),
        CONSTRAINT [FK_AppVisits_UserProfiles_UserId]
            FOREIGN KEY ([UserId]) REFERENCES [UserProfiles] ([UserId])
            ON DELETE NO ACTION
    );
    CREATE INDEX [IX_AppVisits_Created] ON [AppVisits] ([Created]);
    CREATE INDEX [IX_AppVisits_UserId_Created]
        ON [AppVisits] ([UserId], [Created]);
END
GO

IF OBJECT_ID(N'[__MigrationHistory]', N'U') IS NOT NULL
AND NOT EXISTS (
    SELECT 1 FROM [__MigrationHistory]
    WHERE [MigrationId] LIKE N'%AddAppVisit'
)
BEGIN
    IF COL_LENGTH(N'__MigrationHistory', N'ContextKey') IS NOT NULL
        INSERT INTO [__MigrationHistory]
            ([MigrationId], [ContextKey], [Model], [ProductVersion])
        VALUES (N'20260919172928_AddAppVisit',
            N'Domain.Entities.StreamContext', 0x, N'9.0.8');
    ELSE
        INSERT INTO [__MigrationHistory] ([MigrationId], [ProductVersion])
        VALUES (N'20260919172928_AddAppVisit', N'9.0.8');
END
GO
