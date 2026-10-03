IF COL_LENGTH('dbo.Servers', 'AlertRecipients') IS NULL
BEGIN
    ALTER TABLE dbo.Servers ADD AlertRecipients nvarchar(4000) NULL;
END
GO
