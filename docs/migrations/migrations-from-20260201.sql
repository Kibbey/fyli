BEGIN TRANSACTION;
IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260201014219_AddMemoryShareLinks'
)
BEGIN
    DECLARE @var sysname;
    SELECT @var = [d].[name]
    FROM [sys].[default_constraints] [d]
    INNER JOIN [sys].[columns] [c] ON [d].[parent_column_id] = [c].[column_id] AND [d].[parent_object_id] = [c].[object_id]
    WHERE ([d].[parent_object_id] = OBJECT_ID(N'[ShareRequests]') AND [c].[name] = N'PremiumPlanId');
    IF @var IS NOT NULL EXEC(N'ALTER TABLE [ShareRequests] DROP CONSTRAINT [' + @var + '];');
    ALTER TABLE [ShareRequests] ALTER COLUMN [PremiumPlanId] int NULL;
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260201014219_AddMemoryShareLinks'
)
BEGIN
    CREATE TABLE [MemoryShareLinks] (
        [MemoryShareLinkId] int NOT NULL IDENTITY,
        [DropId] int NOT NULL,
        [CreatorUserId] int NOT NULL,
        [Token] uniqueidentifier NOT NULL,
        [IsActive] bit NOT NULL,
        [CreatedAt] datetime2 NOT NULL,
        [ExpiresAt] datetime2 NULL,
        [ViewCount] int NOT NULL,
        CONSTRAINT [PK_MemoryShareLinks] PRIMARY KEY ([MemoryShareLinkId]),
        CONSTRAINT [FK_MemoryShareLinks_Drops_DropId] FOREIGN KEY ([DropId]) REFERENCES [Drops] ([DropId]) ON DELETE NO ACTION,
        CONSTRAINT [FK_MemoryShareLinks_UserProfiles_CreatorUserId] FOREIGN KEY ([CreatorUserId]) REFERENCES [UserProfiles] ([UserId]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260201014219_AddMemoryShareLinks'
)
BEGIN
    CREATE INDEX [IX_MemoryShareLinks_CreatorUserId] ON [MemoryShareLinks] ([CreatorUserId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260201014219_AddMemoryShareLinks'
)
BEGIN
    CREATE INDEX [IX_MemoryShareLinks_DropId] ON [MemoryShareLinks] ([DropId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260201014219_AddMemoryShareLinks'
)
BEGIN
    CREATE UNIQUE INDEX [IX_MemoryShareLinks_Token] ON [MemoryShareLinks] ([Token]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260201014219_AddMemoryShareLinks'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20260201014219_AddMemoryShareLinks', N'9.0.8');
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260206032422_QuestionRequests'
)
BEGIN
    CREATE TABLE [QuestionSets] (
        [QuestionSetId] int NOT NULL IDENTITY,
        [UserId] int NOT NULL,
        [Name] nvarchar(200) NOT NULL,
        [CreatedAt] datetime2 NOT NULL,
        [UpdatedAt] datetime2 NOT NULL,
        [Archived] bit NOT NULL,
        CONSTRAINT [PK_QuestionSets] PRIMARY KEY ([QuestionSetId]),
        CONSTRAINT [FK_QuestionSets_UserProfiles_UserId] FOREIGN KEY ([UserId]) REFERENCES [UserProfiles] ([UserId]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260206032422_QuestionRequests'
)
BEGIN
    CREATE TABLE [QuestionRequests] (
        [QuestionRequestId] int NOT NULL IDENTITY,
        [QuestionSetId] int NOT NULL,
        [CreatorUserId] int NOT NULL,
        [Message] nvarchar(1000) NULL,
        [CreatedAt] datetime2 NOT NULL,
        CONSTRAINT [PK_QuestionRequests] PRIMARY KEY ([QuestionRequestId]),
        CONSTRAINT [FK_QuestionRequests_QuestionSets_QuestionSetId] FOREIGN KEY ([QuestionSetId]) REFERENCES [QuestionSets] ([QuestionSetId]) ON DELETE NO ACTION,
        CONSTRAINT [FK_QuestionRequests_UserProfiles_CreatorUserId] FOREIGN KEY ([CreatorUserId]) REFERENCES [UserProfiles] ([UserId]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260206032422_QuestionRequests'
)
BEGIN
    CREATE TABLE [Questions] (
        [QuestionId] int NOT NULL IDENTITY,
        [QuestionSetId] int NOT NULL,
        [Text] nvarchar(500) NOT NULL,
        [SortOrder] int NOT NULL,
        [CreatedAt] datetime2 NOT NULL,
        CONSTRAINT [PK_Questions] PRIMARY KEY ([QuestionId]),
        CONSTRAINT [FK_Questions_QuestionSets_QuestionSetId] FOREIGN KEY ([QuestionSetId]) REFERENCES [QuestionSets] ([QuestionSetId]) ON DELETE CASCADE
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260206032422_QuestionRequests'
)
BEGIN
    CREATE TABLE [QuestionRequestRecipients] (
        [QuestionRequestRecipientId] int NOT NULL IDENTITY,
        [QuestionRequestId] int NOT NULL,
        [Token] uniqueidentifier NOT NULL,
        [Email] nvarchar(255) NULL,
        [Alias] nvarchar(100) NULL,
        [RespondentUserId] int NULL,
        [IsActive] bit NOT NULL,
        [CreatedAt] datetime2 NOT NULL,
        [RemindersSent] int NOT NULL,
        [LastReminderAt] datetime2 NULL,
        CONSTRAINT [PK_QuestionRequestRecipients] PRIMARY KEY ([QuestionRequestRecipientId]),
        CONSTRAINT [FK_QuestionRequestRecipients_QuestionRequests_QuestionRequestId] FOREIGN KEY ([QuestionRequestId]) REFERENCES [QuestionRequests] ([QuestionRequestId]) ON DELETE CASCADE,
        CONSTRAINT [FK_QuestionRequestRecipients_UserProfiles_RespondentUserId] FOREIGN KEY ([RespondentUserId]) REFERENCES [UserProfiles] ([UserId]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260206032422_QuestionRequests'
)
BEGIN
    CREATE TABLE [QuestionResponses] (
        [QuestionResponseId] int NOT NULL IDENTITY,
        [QuestionRequestRecipientId] int NOT NULL,
        [QuestionId] int NOT NULL,
        [DropId] int NOT NULL,
        [AnsweredAt] datetime2 NOT NULL,
        CONSTRAINT [PK_QuestionResponses] PRIMARY KEY ([QuestionResponseId]),
        CONSTRAINT [FK_QuestionResponses_Drops_DropId] FOREIGN KEY ([DropId]) REFERENCES [Drops] ([DropId]) ON DELETE NO ACTION,
        CONSTRAINT [FK_QuestionResponses_QuestionRequestRecipients_QuestionRequestRecipientId] FOREIGN KEY ([QuestionRequestRecipientId]) REFERENCES [QuestionRequestRecipients] ([QuestionRequestRecipientId]) ON DELETE NO ACTION,
        CONSTRAINT [FK_QuestionResponses_Questions_QuestionId] FOREIGN KEY ([QuestionId]) REFERENCES [Questions] ([QuestionId]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260206032422_QuestionRequests'
)
BEGIN
    CREATE INDEX [IX_QuestionRequestRecipients_Email] ON [QuestionRequestRecipients] ([Email]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260206032422_QuestionRequests'
)
BEGIN
    CREATE INDEX [IX_QuestionRequestRecipients_QuestionRequestId] ON [QuestionRequestRecipients] ([QuestionRequestId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260206032422_QuestionRequests'
)
BEGIN
    CREATE INDEX [IX_QuestionRequestRecipients_RespondentUserId] ON [QuestionRequestRecipients] ([RespondentUserId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260206032422_QuestionRequests'
)
BEGIN
    CREATE UNIQUE INDEX [IX_QuestionRequestRecipients_Token] ON [QuestionRequestRecipients] ([Token]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260206032422_QuestionRequests'
)
BEGIN
    CREATE INDEX [IX_QuestionRequests_CreatorUserId] ON [QuestionRequests] ([CreatorUserId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260206032422_QuestionRequests'
)
BEGIN
    CREATE INDEX [IX_QuestionRequests_QuestionSetId] ON [QuestionRequests] ([QuestionSetId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260206032422_QuestionRequests'
)
BEGIN
    CREATE INDEX [IX_QuestionResponses_AnsweredAt] ON [QuestionResponses] ([AnsweredAt]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260206032422_QuestionRequests'
)
BEGIN
    CREATE UNIQUE INDEX [IX_QuestionResponses_DropId] ON [QuestionResponses] ([DropId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260206032422_QuestionRequests'
)
BEGIN
    CREATE INDEX [IX_QuestionResponses_QuestionId] ON [QuestionResponses] ([QuestionId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260206032422_QuestionRequests'
)
BEGIN
    CREATE UNIQUE INDEX [IX_QuestionResponses_QuestionRequestRecipientId_QuestionId] ON [QuestionResponses] ([QuestionRequestRecipientId], [QuestionId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260206032422_QuestionRequests'
)
BEGIN
    CREATE INDEX [IX_Questions_QuestionSetId] ON [Questions] ([QuestionSetId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260206032422_QuestionRequests'
)
BEGIN
    CREATE INDEX [IX_QuestionSets_UserId] ON [QuestionSets] ([UserId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260206032422_QuestionRequests'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20260206032422_QuestionRequests', N'9.0.8');
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260209005943_AddExternalLogin'
)
BEGIN
    CREATE TABLE [ExternalLogins] (
        [ExternalLoginId] int NOT NULL IDENTITY,
        [UserId] int NOT NULL,
        [Provider] varchar(50) NOT NULL,
        [ProviderUserId] varchar(256) NOT NULL,
        [Email] varchar(256) NOT NULL,
        [LinkedAt] datetime2 NOT NULL,
        CONSTRAINT [PK_ExternalLogins] PRIMARY KEY ([ExternalLoginId]),
        CONSTRAINT [FK_ExternalLogins_UserProfiles_UserId] FOREIGN KEY ([UserId]) REFERENCES [UserProfiles] ([UserId]) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260209005943_AddExternalLogin'
)
BEGIN
    CREATE UNIQUE INDEX [IX_ExternalLogins_Provider_ProviderUserId] ON [ExternalLogins] ([Provider], [ProviderUserId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260209005943_AddExternalLogin'
)
BEGIN
    CREATE INDEX [IX_ExternalLogins_UserId] ON [ExternalLogins] ([UserId]);
END;

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20260209005943_AddExternalLogin'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20260209005943_AddExternalLogin', N'9.0.8');
END;

COMMIT;
GO
