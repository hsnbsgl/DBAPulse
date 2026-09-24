CREATE INDEX IX_CapacitySnapshots_DatabaseCollected ON dbo.CapacitySnapshots(DatabaseId, CollectedAtUtc DESC) INCLUDE (FileType, AllocatedSizeMb);
CREATE INDEX IX_CapacitySnapshots_ServerCollected ON dbo.CapacitySnapshots(ServerId, CollectedAtUtc DESC) INCLUDE (DatabaseId, FileType, AllocatedSizeMb);
CREATE INDEX IX_VolumeCapacitySnapshots_VolumeCollected ON dbo.VolumeCapacitySnapshots(ServerId, VolumeId, CollectedAtUtc DESC) INCLUDE (TotalBytes, AvailableBytes);
