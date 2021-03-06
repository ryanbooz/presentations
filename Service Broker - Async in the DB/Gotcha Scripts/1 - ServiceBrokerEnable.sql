
/****** Object:  StoredProcedure [dbo].[ServiceBrokerEnable]    Script Date: 11/7/2018 7:53:55 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* 
 * PROCEDURE: dbo.ServiceBrokerEnable 
 */

ALTER PROCEDURE [dbo].[ServiceBrokerEnable]
AS
BEGIN
	DECLARE @dbname varchar(200) = DB_NAME()
	DECLARE @is_broker_enabled bit
	DECLARE @exec_str varchar(2000)
	
	SELECT @is_broker_enabled = is_broker_enabled FROM sys.databases WHERE name = @dbname
	SELECT @dbname = '[' + @dbname + ']'
	
	IF @is_broker_enabled = 0
	BEGIN
		PRINT 'SB is not enabled, enabling...'
		DECLARE @Status sql_variant
		SELECT @Status = DATABASEPROPERTYEX(DB_NAME(),'UserAccess')
		
		IF @Status <> 'SINGLE_USER'
		BEGIN
			SELECT @exec_str = 'ALTER DATABASE ' + @dbname + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;'
			PRINT @exec_str + '...'
			EXEC (@exec_str)
		END
		
		SELECT @exec_str = 'ALTER DATABASE ' + @dbname + ' SET ENABLE_BROKER;'
		PRINT @exec_str + '...'
		BEGIN TRY
			EXEC (@exec_str)
		END TRY
		BEGIN CATCH
			--need to do this in case we have a backed up db on the same system as the source.  This resets the ID,
			--but also blows away all existing conversations without producing end dialog messages.  Any route that
			--references the old SB ID must be recreated.
			SELECT @exec_str = 'ALTER DATABASE ' + @dbname + ' SET NEW_BROKER;'
			PRINT @exec_str + '...'
			EXEC (@exec_str)
		END CATCH
		
		--return the database to its previous state
		IF @Status = 'MULTI_USER'
		BEGIN
			SELECT @exec_str = 'ALTER DATABASE ' + @dbname + ' SET MULTI_USER;'
			PRINT @exec_str + '...'
			EXEC (@exec_str)
		END;
		ELSE
		IF @Status = 'RESTRICTED_USER'
		BEGIN
			SELECT @exec_str = 'ALTER DATABASE ' + @dbname + ' SET RESTRICTED_USER;'
			PRINT @exec_str + '...'
			EXEC (@exec_str)
		END;
	END;
	ELSE
	BEGIN
		PRINT 'SB is enabled, no work to do.'
	END;
	
	-- ALTER AUTHORIZATION deadlocks in long scripts,
	-- retry upto 30 times in try/catch
	DECLARE @retry_count INT
	SELECT @retry_count = 0
	WHILE (@retry_count < 30)
	BEGIN
		BEGIN TRY
			SELECT @exec_str = 'ALTER DATABASE ' + @dbname + ' SET TRUSTWORTHY ON;'
			PRINT @exec_str + '...'
			EXEC (@exec_str)
	
			SELECT @exec_str = 'ALTER AUTHORIZATION ON DATABASE::' + @dbname + ' TO SA;'
			PRINT @exec_str + '...'
			EXEC (@exec_str)

			BREAK
		END TRY
		BEGIN CATCH
			WAITFOR DELAY '00:00:01'
			SELECT @retry_count = @retry_count + 1
			PRINT 'Waiting for database authorization to be updated, retry count = ' + CONVERT(VARCHAR, @retry_count)
			CONTINUE
		END CATCH
	END
END;


