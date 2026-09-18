-- ============================================================================
-- Index drift audit: what the EF model declares vs what production actually has
--
-- Generated from cimplur-core/Memento/Domain/Migrations/StreamContextModelSnapshot.cs
-- (75 declared indexes across 37 tables).
--
-- WHY THIS EXISTS
-- The 2026-09-09 GetTimeline timeout was caused by indexes that the EF model
-- declared but that never landed on the EF6-era production schema. The 09-09
-- catch-up script fixed only the seven on the GetTimeline path. This checks the
-- whole schema.
--
-- HOW IT MATCHES
-- By COLUMN LIST, not index name. Production uses EF6-era PK_dbo.* naming, so
-- name matching would report false gaps. An expected index is considered
-- satisfied if any existing index's KEY COLUMNS START WITH the expected columns
-- in order -- a composite (UserId, TimelineId) does satisfy an expected (UserId).
--
-- Read-only. Safe to run on production at any time.
-- ============================================================================

-- QUOTED_IDENTIFIER must be ON for the FOR XML PATH .value() calls below.
-- sqlcmd does not set it by default, which is why it is explicit here.
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;

DECLARE @expected TABLE (table_name sysname, cols nvarchar(400), is_unique bit);

INSERT INTO @expected (table_name, cols, is_unique) VALUES
    (N'AlbumDrops', N'DropId', 0),
    (N'AlbumExports', N'AlbumId', 0),
    (N'Albums', N'UserId', 0),
    (N'CacheEntries', N'CacheKey', 0),
    (N'CacheEntries', N'ExpiresAt', 0),
    (N'Comments', N'DropId', 0),
    (N'Comments', N'UserId', 0),
    (N'Drops', N'CompletedByUserId', 0),
    (N'Drops', N'ParentDropId', 0),
    (N'Drops', N'PromptId', 0),
    (N'Drops', N'TimelineId', 0),
    (N'Drops', N'UserId', 0),
    (N'ExternalLogins', N'Provider,ProviderUserId', 1),
    (N'ExternalLogins', N'UserId', 0),
    (N'ImageDrops', N'CommentId', 0),
    (N'ImageDrops', N'DropId', 0),
    (N'MemoryShareLinks', N'CreatorUserId', 0),
    (N'MemoryShareLinks', N'DropId', 0),
    (N'MemoryShareLinks', N'Token', 1),
    (N'MovieDrops', N'CommentId', 0),
    (N'MovieDrops', N'DropId', 0),
    (N'NetworkDrops', N'DropId', 0),
    (N'NetworkDrops', N'UserTagId,DropId', 1),
    (N'NetworkViewers', N'UserId', 0),
    (N'PremiumPlans', N'ParentPremiumPlanId', 0),
    (N'PremiumPlans', N'TransactionId', 0),
    (N'PremiumPlans', N'UserId', 0),
    (N'PromptTimelines', N'PromptId,TimelineId', 1),
    (N'PromptTimelines', N'TimelineId', 0),
    (N'Prompts', N'UserId', 0),
    (N'QuestionRequestRecipients', N'Email', 0),
    (N'QuestionRequestRecipients', N'QuestionRequestId', 0),
    (N'QuestionRequestRecipients', N'RespondentUserId', 0),
    (N'QuestionRequestRecipients', N'Token', 1),
    (N'QuestionRequests', N'CreatorUserId', 0),
    (N'QuestionRequests', N'QuestionSetId', 0),
    (N'QuestionResponses', N'AnsweredAt', 0),
    (N'QuestionResponses', N'DropId', 1),
    (N'QuestionResponses', N'QuestionId', 0),
    (N'QuestionResponses', N'QuestionRequestRecipientId,QuestionId', 1),
    (N'QuestionSets', N'UserId', 0),
    (N'Questions', N'QuestionSetId', 0),
    (N'ShareRequests', N'PremiumPlanId', 0),
    (N'ShareRequests', N'RequesterUserId', 0),
    (N'ShareRequests', N'TargetsUserId', 0),
    (N'SharedDropNotifications', N'DropId', 0),
    (N'SharedDropNotifications', N'SharerUserId', 0),
    (N'SharedDropNotifications', N'TargetUserId', 0),
    (N'SharedPlans', N'SharedPremiumPlanId', 0),
    (N'SharedPlans', N'UserId', 0),
    (N'SharingSuggestions', N'SuggestedUserId', 0),
    (N'TimelineDrops', N'DropId', 0),
    (N'TimelineDrops', N'UserId', 0),
    (N'TimelineShareLinks', N'CreatorUserId', 0),
    (N'TimelineShareLinks', N'TimelineId', 0),
    (N'TimelineShareLinks', N'Token', 1),
    (N'TimelineUsers', N'TimelineId', 0),
    (N'TimelineUsers', N'UserId,TimelineId', 1),
    (N'Timelines', N'UserId', 0),
    (N'Transactions', N'UserId', 0),
    (N'UserDrops', N'DropId', 0),
    (N'UserDrops', N'UserId', 0),
    (N'UserEmails', N'UserId', 0),
    (N'UserNetworks', N'UserId,Name', 1),
    (N'UserProfiles', N'UserId,PremiumExpiration', 0),
    (N'UserPromptAskers', N'AskerId', 0),
    (N'UserPromptAskers', N'UserPromptId', 0),
    (N'UserPrompts', N'LastSeen', 0),
    (N'UserPrompts', N'PromptId', 0),
    (N'UserPrompts', N'PromptId,UserId', 1),
    (N'UserPrompts', N'UserId', 0),
    (N'UserRelationships', N'UserId,Relationship', 1),
    (N'UserUsers', N'OwnerUserId', 0),
    (N'UserUsers', N'ReaderUserId', 0),
    (N'UserUsers', N'ReaderUserId,OwnerUserId', 1);

WITH actual AS (
    SELECT
        t.name AS table_name,
        i.name AS index_name,
        i.is_unique,
        i.type_desc,
        STUFF((
            SELECT ',' + c.name
            FROM sys.index_columns ic
            JOIN sys.columns c
              ON c.object_id = ic.object_id AND c.column_id = ic.column_id
            WHERE ic.object_id = i.object_id
              AND ic.index_id  = i.index_id
              AND ic.is_included_column = 0
            ORDER BY ic.key_ordinal
            FOR XML PATH(''), TYPE
        ).value('.', 'nvarchar(400)'), 1, 1, '') AS key_cols
    FROM sys.indexes i
    JOIN sys.tables  t ON t.object_id = i.object_id
    WHERE i.type > 0          -- exclude heaps
      AND i.is_hypothetical = 0
      AND i.is_disabled = 0
)
SELECT
    e.table_name                          AS [Table],
    e.cols                                AS [Expected columns],
    CASE WHEN e.is_unique = 1 THEN 'UNIQUE' ELSE '' END AS [Unique],
    CASE
        WHEN OBJECT_ID(QUOTENAME(e.table_name)) IS NULL THEN 'TABLE MISSING'
        ELSE 'INDEX MISSING'
    END                                   AS [Problem],
    N'CREATE ' + CASE WHEN e.is_unique = 1 THEN N'UNIQUE ' ELSE N'' END
      + N'NONCLUSTERED INDEX [IX_' + e.table_name + N'_'
      + REPLACE(e.cols, N',', N'_') + N'] ON ' + QUOTENAME(e.table_name)
      + N' (' + e.cols + N');'            AS [Fix]
FROM @expected e
WHERE NOT EXISTS (
    SELECT 1
    FROM actual a
    WHERE a.table_name = e.table_name
      -- prefix match: existing key columns start with the expected columns
      AND (a.key_cols = e.cols OR a.key_cols LIKE e.cols + N',%')
)
ORDER BY
    CASE WHEN OBJECT_ID(QUOTENAME(e.table_name)) IS NULL THEN 1 ELSE 0 END,
    e.table_name, e.cols;

-- Summary line
WITH actual AS (
    SELECT t.name AS table_name,
        STUFF((SELECT ',' + c.name FROM sys.index_columns ic
               JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
               WHERE ic.object_id=i.object_id AND ic.index_id=i.index_id AND ic.is_included_column=0
               ORDER BY ic.key_ordinal FOR XML PATH(''), TYPE).value('.','nvarchar(400)'),1,1,'') AS key_cols
    FROM sys.indexes i JOIN sys.tables t ON t.object_id=i.object_id
    WHERE i.type > 0 AND i.is_hypothetical = 0
      AND i.is_disabled = 0
)
SELECT
    (SELECT COUNT(*) FROM @expected) AS [Declared in model],
    (SELECT COUNT(*) FROM @expected e WHERE NOT EXISTS (
        SELECT 1 FROM actual a WHERE a.table_name = e.table_name
          AND (a.key_cols = e.cols OR a.key_cols LIKE e.cols + N',%'))) AS [Missing in prod];
