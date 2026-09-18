-- AddAdminAudit. Safe to re-run. Run after AddAsk.sql (FK to Asks).
-- Production history table is EF6 [__MigrationHistory], not EF Core [__EFMigrationsHistory].

IF OBJECT_ID(N'[AdminAudits]', N'U') IS NULL
BEGIN
    CREATE TABLE [AdminAudits] (
        [AdminAuditId] INT IDENTITY(1,1) NOT NULL,
        [AdminUserId] INT NOT NULL,
        [TargetUserId] INT NOT NULL,
        [Action] VARCHAR(32) NOT NULL,
        [OldValue] VARCHAR(100) NULL,
        [NewValue] VARCHAR(100) NULL,
        [Created] DATETIME2 NOT NULL,
        [DisputeToken] UNIQUEIDENTIFIER NOT NULL,
        [DisputeTokenExpires] DATETIME2 NOT NULL,
        [DisputeTokenUsedAt] DATETIME2 NULL,
        [DisputeAskId] INT NULL,
        CONSTRAINT [PK_AdminAudits] PRIMARY KEY ([AdminAuditId]),
        CONSTRAINT [FK_AdminAudits_UserProfiles_AdminUserId]
            FOREIGN KEY ([AdminUserId]) REFERENCES [UserProfiles] ([UserId]) ON DELETE NO ACTION,
        CONSTRAINT [FK_AdminAudits_UserProfiles_TargetUserId]
            FOREIGN KEY ([TargetUserId]) REFERENCES [UserProfiles] ([UserId]) ON DELETE NO ACTION,
        CONSTRAINT [FK_AdminAudits_Asks_DisputeAskId]
            FOREIGN KEY ([DisputeAskId]) REFERENCES [Asks] ([AskId]) ON DELETE NO ACTION
    );
    CREATE INDEX [IX_AdminAudits_AdminUserId] ON [AdminAudits] ([AdminUserId]);
    CREATE INDEX [IX_AdminAudits_Created] ON [AdminAudits] ([Created]);
    CREATE INDEX [IX_AdminAudits_DisputeAskId] ON [AdminAudits] ([DisputeAskId]);
    CREATE UNIQUE INDEX [IX_AdminAudits_DisputeToken] ON [AdminAudits] ([DisputeToken]);
    CREATE INDEX [IX_AdminAudits_TargetUserId] ON [AdminAudits] ([TargetUserId]);
END
GO

IF OBJECT_ID(N'[__MigrationHistory]', N'U') IS NOT NULL
AND NOT EXISTS (
    SELECT 1 FROM [__MigrationHistory]
    WHERE [MigrationId] = N'20260918020101_AddAdminAudit'
)
BEGIN
    IF COL_LENGTH(N'__MigrationHistory', N'ContextKey') IS NOT NULL
        INSERT INTO [__MigrationHistory] ([MigrationId], [ContextKey], [Model], [ProductVersion])
        VALUES (N'20260918020101_AddAdminAudit', N'Domain.Entities.StreamContext', 0x, N'9.0.8');
    ELSE
        INSERT INTO [__MigrationHistory] ([MigrationId], [ProductVersion])
        VALUES (N'20260918020101_AddAdminAudit', N'9.0.8');
END
GO
