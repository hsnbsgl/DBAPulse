CREATE TABLE dbo.CollectionRuns
(
    Id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_CollectionRuns PRIMARY KEY,
    StartedAtUtc datetime2(3) NOT NULL,
    FinishedAtUtc datetime2(3) NULL,
    Status nvarchar(30) NOT NULL,
    DurationMs bigint NULL
);

CREATE TABLE dbo.CollectionErrors
(
    Id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_CollectionErrors PRIMARY KEY,
    CollectionRunId bigint NOT NULL,
    QueryName nvarchar(256) NOT NULL,
    ServerName nvarchar(256) NULL,
    ErrorMessage nvarchar(4000) NOT NULL,
    CreatedAtUtc datetime2(3) NOT NULL,
    CONSTRAINT FK_CollectionErrors_CollectionRuns FOREIGN KEY (CollectionRunId) REFERENCES dbo.CollectionRuns(Id)
);
GO
