-- Grant admin to kibbeyj@gmail.com. Safe to re-run.
-- Fails if that UserProfile does not exist.

IF NOT EXISTS (
    SELECT 1 FROM [UserProfiles]
    WHERE LOWER([Email]) = N'kibbeyj@gmail.com'
)
BEGIN
    THROW 50001, 'Admin seed failed: no UserProfile with email kibbeyj@gmail.com', 1;
END;

INSERT INTO [UserRoles] ([UserId], [Role], [Created])
SELECT u.[UserId], 'admin', SYSUTCDATETIME()
FROM [UserProfiles] u
WHERE LOWER(u.[Email]) = N'kibbeyj@gmail.com'
  AND NOT EXISTS (
      SELECT 1 FROM [UserRoles] r
      WHERE r.[UserId] = u.[UserId] AND r.[Role] = 'admin'
  );
