CREATE OR ALTER PROCEDURE dbo.usp_AuditLog_Insert
    @OccurredAtUtc datetime2(3),
    @UserName nvarchar(256),
    @Action nvarchar(128),
    @ResourceType nvarchar(64),
    @HttpMethod nvarchar(16),
    @RequestPath nvarchar(512),
    @Result nvarchar(16),
    @StatusCode int,
    @DurationMs bigint,
    @CorrelationId nvarchar(64),
    @UserRole nvarchar(128) = NULL,
    @ResourceId nvarchar(128) = NULL,
    @ClientIp nvarchar(128) = NULL,
    @UserAgent nvarchar(512) = NULL,
    @AdditionalData nvarchar(2000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.AuditLogs
    (OccurredAtUtc, UserName, UserRole, Action, ResourceType, ResourceId, HttpMethod, RequestPath, Result, StatusCode, DurationMs, CorrelationId, ClientIp, UserAgent, AdditionalData)
    VALUES
    (@OccurredAtUtc, @UserName, @UserRole, @Action, @ResourceType, @ResourceId, @HttpMethod, @RequestPath, @Result, @StatusCode, @DurationMs, @CorrelationId, @ClientIp, @UserAgent, @AdditionalData);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AuditLogs_List
    @FromUtc datetime2(3) = NULL,
    @ToUtc datetime2(3) = NULL,
    @UserName nvarchar(256) = NULL,
    @Action nvarchar(128) = NULL,
    @ResourceType nvarchar(64) = NULL,
    @Result nvarchar(16) = NULL,
    @CorrelationId nvarchar(64) = NULL,
    @Page int = 1,
    @PageSize int = 50
AS
BEGIN
    SET NOCOUNT ON;
    SET @Page = CASE WHEN @Page < 1 THEN 1 ELSE @Page END;
    SET @PageSize = CASE WHEN @PageSize < 1 THEN 50 WHEN @PageSize > 100 THEN 100 ELSE @PageSize END;
    SELECT Id, OccurredAtUtc, UserName, UserRole, Action, ResourceType, ResourceId, HttpMethod, RequestPath, Result, StatusCode, DurationMs, CorrelationId, ClientIp, UserAgent, AdditionalData
    FROM dbo.AuditLogs
    WHERE (@FromUtc IS NULL OR OccurredAtUtc >= @FromUtc)
      AND (@ToUtc IS NULL OR OccurredAtUtc <= @ToUtc)
      AND (@UserName IS NULL OR UserName LIKE N'%' + @UserName + N'%')
      AND (@Action IS NULL OR Action = @Action)
      AND (@ResourceType IS NULL OR ResourceType = @ResourceType)
      AND (@Result IS NULL OR Result = @Result)
      AND (@CorrelationId IS NULL OR CorrelationId = @CorrelationId)
    ORDER BY OccurredAtUtc DESC, Id DESC
    OFFSET (@Page - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT COUNT(*) AS TotalCount FROM dbo.AuditLogs
    WHERE (@FromUtc IS NULL OR OccurredAtUtc >= @FromUtc)
      AND (@ToUtc IS NULL OR OccurredAtUtc <= @ToUtc)
      AND (@UserName IS NULL OR UserName LIKE N'%' + @UserName + N'%')
      AND (@Action IS NULL OR Action = @Action)
      AND (@ResourceType IS NULL OR ResourceType = @ResourceType)
      AND (@Result IS NULL OR Result = @Result)
      AND (@CorrelationId IS NULL OR CorrelationId = @CorrelationId);
END;
GO
