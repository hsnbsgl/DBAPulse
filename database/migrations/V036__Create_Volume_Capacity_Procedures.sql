CREATE TYPE dbo.VolumeCapacitySnapshotInputType AS TABLE
(
    CollectionRunId bigint NOT NULL, ServerId int NOT NULL, VolumeId nvarchar(512) NOT NULL,
    CollectedAtUtc datetime2(3) NOT NULL, TotalBytes bigint NOT NULL, AvailableBytes bigint NOT NULL
);
GO
CREATE OR ALTER PROCEDURE dbo.usp_VolumeCapacitySnapshots_Insert @Rows dbo.VolumeCapacitySnapshotInputType READONLY AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.VolumeCapacitySnapshots(CollectionRunId,ServerId,VolumeId,CollectedAtUtc,TotalBytes,AvailableBytes)
 SELECT CollectionRunId,ServerId,VolumeId,CollectedAtUtc,TotalBytes,AvailableBytes FROM @Rows;
 SELECT CAST(@@ROWCOUNT AS int);
END;
