/*
   Non-Prod backup scope default.
   - Dev/Test/Stage databases that were not explicitly selected are Excluded.
   - Required remains available as an explicit opt-in.
   - Prod policy and mirrored-database exemption are evaluated by the protection procedures.
   - No mock data is inserted.
*/

UPDATE dbo.Databases
   SET BackupProtectionMode = N'Excluded'
 WHERE BackupProtectionMode = N'Auto';
GO

IF EXISTS
(
    SELECT 1
    FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.Databases')
      AND name = N'DF_Databases_BackupProtectionMode'
)
    ALTER TABLE dbo.Databases DROP CONSTRAINT DF_Databases_BackupProtectionMode;
GO

ALTER TABLE dbo.Databases
    ADD CONSTRAINT DF_Databases_BackupProtectionMode DEFAULT N'Excluded' FOR BackupProtectionMode;
GO
