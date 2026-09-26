ALTER TABLE dbo.Servers ADD
    CollectionIntervalMinutes int NOT NULL CONSTRAINT DF_Servers_CollectionIntervalMinutes DEFAULT (5),
    CapacityIntervalMinutes int NOT NULL CONSTRAINT DF_Servers_CapacityIntervalMinutes DEFAULT (60);
GO

ALTER TABLE dbo.Servers ADD CONSTRAINT CK_Servers_CollectionIntervalMinutes CHECK (CollectionIntervalMinutes BETWEEN 1 AND 1440);
ALTER TABLE dbo.Servers ADD CONSTRAINT CK_Servers_CapacityIntervalMinutes CHECK (CapacityIntervalMinutes BETWEEN 1 AND 1440);
GO