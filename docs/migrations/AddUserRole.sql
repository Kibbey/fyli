-- AddUserRole. Safe to re-run.
-- Production history table is EF6 [__MigrationHistory], not EF Core [__EFMigrationsHistory].
-- Table create is gated on OBJECT_ID so it still works if history columns differ.

IF OBJECT_ID(N'[UserRoles]', N'U') IS NULL
BEGIN
    CREATE TABLE [UserRoles] (
        [UserRoleId] INT IDENTITY(1,1) NOT NULL,
        [UserId] INT NOT NULL,
        [Role] VARCHAR(32) NOT NULL,
        [Created] DATETIME2 NOT NULL,
        CONSTRAINT [PK_UserRoles] PRIMARY KEY ([UserRoleId]),
        CONSTRAINT [FK_UserRoles_UserProfiles_UserId]
            FOREIGN KEY ([UserId]) REFERENCES [UserProfiles] ([UserId]) ON DELETE NO ACTION
    );
    CREATE UNIQUE INDEX [IX_UserRoles_UserId_Role] ON [UserRoles] ([UserId], [Role]);
    CREATE INDEX [IX_UserRoles_Role] ON [UserRoles] ([Role]);
END
GO

IF OBJECT_ID(N'[__MigrationHistory]', N'U') IS NOT NULL
AND NOT EXISTS (
    SELECT 1 FROM [__MigrationHistory]
    WHERE [MigrationId] = N'20260918015825_AddUserRole'
)
BEGIN
    IF COL_LENGTH(N'__MigrationHistory', N'ContextKey') IS NOT NULL
        INSERT INTO [__MigrationHistory] ([MigrationId], [ContextKey], [Model], [ProductVersion])
        VALUES (N'20260918015825_AddUserRole', N'Domain.Entities.StreamContext', 0x, N'9.0.8');
    ELSE
        INSERT INTO [__MigrationHistory] ([MigrationId], [ProductVersion])
        VALUES (N'20260918015825_AddUserRole', N'9.0.8');
END
GO
