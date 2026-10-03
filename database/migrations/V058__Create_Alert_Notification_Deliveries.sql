CREATE TABLE dbo.AlertNotificationDeliveries
(
    OperationalEventId bigint NOT NULL CONSTRAINT PK_AlertNotificationDeliveries PRIMARY KEY,
    SentAtUtc datetime2(3) NOT NULL CONSTRAINT DF_AlertNotificationDeliveries_SentAtUtc DEFAULT (SYSUTCDATETIME()),
    Severity nvarchar(20) NOT NULL,
    RecipientList nvarchar(2000) NOT NULL,
    CONSTRAINT FK_AlertNotificationDeliveries_OperationalEvent FOREIGN KEY (OperationalEventId) REFERENCES dbo.OperationalEvents(Id)
);
GO

CREATE INDEX IX_AlertNotificationDeliveries_SentAtUtc ON dbo.AlertNotificationDeliveries(SentAtUtc DESC);
GO
