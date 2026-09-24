CREATE TABLE dbo.VolumeCapacitySnapshots
(
    Id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_VolumeCapacitySnapshots PRIMARY KEY,
    CollectionRunId bigint NULL,
    ServerId int NOT NULL,
    VolumeId nvarchar(512) NOT NULL,
    CollectedAtUtc datetime2(3) NOT NULL,
    TotalBytes bigint NOT NULL,
    AvailableBytes bigint NOT NULL
);
