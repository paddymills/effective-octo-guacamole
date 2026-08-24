
USE SNInterDev;
GO

CREATE OR ALTER PROCEDURE cds.ApplyPlannerStateJson
    @Plant VARCHAR(64),
    @Bay VARCHAR(64),
    @StateJson NVARCHAR(MAX),
    @UserName VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Parse JSON into a structured table with an Action field
    DECLARE @Incoming TABLE (
        ProgramName VARCHAR(50) PRIMARY KEY,
        MachineName VARCHAR(50),
        ScheduledBurnDate DATE,
        SortOrder INT,
        Action VARCHAR(16)
    );

    INSERT INTO @Incoming (ProgramName, MachineName, ScheduledBurnDate, SortOrder)
    SELECT
        programName,
        machineName,
        CAST(scheduledBurnDate AS DATE),
        newIndex
    FROM OPENJSON(@StateJson)
    WITH (
        programName VARCHAR(50),
        machineName VARCHAR(50),
        scheduledBurnDate VARCHAR(50),
        newIndex INT
    );

    -- 2. Identify items that are already in the database
    -- Mark as UPDATE if they differ
    UPDATE inc
    SET Action = CASE
        WHEN ISNULL(mp.ScheduledBurnDate, '1900-01-01') <> inc.ScheduledBurnDate OR
             ISNULL(mp.SortOrder, -1) <> inc.SortOrder OR
             ISNULL(mp.MachineName, '') <> inc.MachineName THEN 'UPDATE'
        ELSE 'NONE'
    END
    FROM @Incoming inc
    INNER JOIN cds.MaterialPlanner mp
    	ON mp.ProgramName = inc.ProgramName
     	AND mp.RequestType = 'Haul In';

    -- 3. Items remaining without an action are new (ADD)
    UPDATE @Incoming
    SET Action = 'ADD'
    WHERE Action IS NULL;

    -- 4. Identify items that need to be UNSCHEDULED
    -- These are items currently in the MaterialPlanner for this Bay/Plant but missing from the incoming JSON
    INSERT INTO @Incoming (ProgramName, MachineName, ScheduledBurnDate, SortOrder, Action)
    SELECT
        mp.ProgramName,
        mp.MachineName,
        NULL, -- ScheduledBurnDate
        NULL, -- SortOrder
        'REMOVE'
    FROM cds.MaterialPlanner mp
    INNER JOIN cds.Machines m
    	ON m.MachineName = mp.MachineName
    LEFT JOIN @Incoming inc
    	ON inc.ProgramName = mp.ProgramName
    WHERE m.Plant = @Plant
      AND m.Bay = @Bay
      AND mp.RequestType = 'Haul In'
      AND inc.ProgramName IS NULL;

    -- 5. Remove items with no changes to simplify processing
    DELETE FROM @Incoming WHERE Action = 'NONE';

    -- Exit if there are no changes to apply
    IF NOT EXISTS (SELECT 1 FROM @Incoming) RETURN;

    BEGIN TRANSACTION;
    BEGIN TRY

        -- 6. Unified Logging for all changes
        INSERT INTO log.MaterialPlanner (Action, ProgramName, MachineName, ScheduledBurnDate, SortOrder, ScheduledBy)
        SELECT Action, ProgramName, MachineName, ScheduledBurnDate, SortOrder, @UserName
        FROM @Incoming;

        -- 7. Apply Updates and Unschedule (setting values to NULL)
        UPDATE mp
        SET
            MachineName = inc.MachineName,
            ScheduledBurnDate = inc.ScheduledBurnDate,
            SortOrder = inc.SortOrder,
            ModifiedDateTime = GETDATE()
        FROM cds.MaterialPlanner mp
        INNER JOIN @Incoming inc
        	ON inc.ProgramName = mp.ProgramName
        WHERE inc.Action IN ('UPDATE', 'REMOVE');

        -- 8. Apply Additions
        INSERT INTO cds.MaterialPlanner (ProgramName, MachineName, ScheduledBurnDate, SortOrder, RequestType)
        SELECT ProgramName, MachineName, ScheduledBurnDate, SortOrder, 'Haul In'
        FROM @Incoming
        WHERE Action = 'ADD';

        -- 9. Delete Removals
        DELETE FROM cds.MaterialPlanner
        WHERE RequestType = 'Haul In'
        AND ScheduledBurnDate IS NULL;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE cds.CleanMaterialPlanner
AS
BEGIN
	-- [1] Remove any haul-in items that are burned
	--	We will add some buffer (1h) so that items don't drop off the planner
	--	if CAD/CAM deletes a program before re-posting it
	--	(otherwise we'll lose priority)
	WITH LastUpdate AS (
		SELECT DISTINCT
			Program.ProgramName,
			LAST_VALUE(Status.DBEntryDateTime) OVER (
				PARTITION BY Program.ProgramName
				ORDER BY Program.ProgramName
			) AS LastStatusDateTime
		FROM oys.Status
		INNER JOIN oys.Program
			ON Program.ProgramGUID=Status.ProgramGUID
	),
	RemovePrograms AS (
		SELECT
			ProgramName
		FROM LastUpdate
		WHERE ProgramName NOT IN (
			SELECT ProgramName
			FROM sap.ActivePrograms
		)
		AND DATEDIFF(Hour, LastStatusDateTime, CURRENT_TIMESTAMP) > 1
	)
	DELETE FROM cds.MaterialPlanner
	WHERE ProgramName IN ( SELECT ProgramName FROM RemovePrograms );

	-- move any past haul-in items to today
	UPDATE cds.MaterialPlanner
	SET
		ModifiedDateTime=CURRENT_TIMESTAMP,
		ScheduledBurnDate=CAST(CURRENT_TIMESTAMP AS DATE)
	WHERE
		ScheduledBurnDate IS NOT NULL
	AND
		ScheduledBurnDate < CAST(CURRENT_TIMESTAMP AS DATE);


	-- [2] remove any Haul Out items that should drop off the list
	-- (Batch is no longer in a machine storage location)
	DELETE FROM cds.MaterialPlanner
	WHERE RequestType = 'Haul Out'
	AND SheetName NOT IN (
		SELECT SheetName
		FROM inv.Batches
		WHERE SLoc IN (
			SELECT SLoc
			FROM cds.Machines
		)
	);

	-- [3] move any past haul-in items to today
	UPDATE cds.MaterialPlanner
	SET
		ModifiedDateTime=CURRENT_TIMESTAMP,
		ScheduledBurnDate=CAST(CURRENT_TIMESTAMP AS DATE)
	WHERE
		ScheduledBurnDate IS NOT NULL
	AND
		ScheduledBurnDate < CAST(CURRENT_TIMESTAMP AS DATE);
END;
GO

CREATE OR ALTER PROCEDURE cds.SyncMaterialPlannerSnapshot
	@afterDateTime DATETIME = NULL
AS
BEGIN
	-- [1] Remove complete items from haul-in/out
	-- [2] move any past haul-in items to today
	-- [3] Update cds.MaterialPlannerSnapshot
	-- [4] Add new items into cds.MaterialPlannerSnapshot
	-- [5] delete items no longer in cds.MaterialPlanner
	-- [6] return results
	
	-- [1] Remove complete items from haul-in/out
	-- [2] move any past haul-in items to today
	EXEC cds.CleanMaterialPlanner;

	-- [3] Update cds.MaterialPlannerSnapshot
	UPDATE dest
	SET
		-- PlannerId, RequestType, ProgramName, SheetIndex should not change
		dest.ModifiedDateTime  = src.ModifiedDateTime,
		dest.Plant             = src.Plant,
		dest.Bay               = src.Bay,
		dest.MachineName       = src.MachineName,
		dest.ScheduledBurnDate = src.ScheduledBurnDate,
		dest.Priority          = src.Priority,
		dest.MaterialMaster    = src.MaterialMaster,
		dest.Batch             = src.Batch,
		dest.Weight            = src.Weight,
		dest.Thickness         = src.Thickness,
		dest.Width             = src.Width,
		dest.Length            = src.Length,
		dest.SLoc              = src.SLoc,
		dest.JobShipment       = src.JobShipment,
		dest.PreBlast          = src.PreBlast,
		dest.Destination       = src.Destination,
		dest.Notes             = src.Notes,
		dest.HashValue         = src.HashValue,
		dest.IsActive          = 1	-- because we updated it, we need to make sure its active
	FROM cds.MaterialPlannerSnapshot dest
	INNER JOIN cds.ExpandedMaterialPlanner src
		ON src.PlannerId  = dest.PlannerId
		AND src.SheetIndex = dest.SheetIndex
	WHERE src.HashValue != dest.HashValue;

	-- [4] Add new items into cds.MaterialPlannerSnapshot
	INSERT INTO cds.MaterialPlannerSnapshot (
		PlannerId,
		ModifiedDateTime,
		RequestType,
		ProgramName,
		SheetIndex,
		Plant,
		Bay,
		MachineName,
		ScheduledBurnDate,
		Priority,
		MaterialMaster,
		Batch,
		Weight,
		Thickness,
		Width,
		Length,
		SLoc,
		JobShipment,
		PreBlast,
		Destination,
		Notes,
		HashValue
	)
	SELECT
		PlannerId,
		ModifiedDateTime,
		RequestType,
		ProgramName,
		SheetIndex,
		Plant,
		Bay,
		MachineName,
		ScheduledBurnDate,
		Priority,
		MaterialMaster,
		Batch,
		Weight,
		Thickness,
		Width,
		Length,
		SLoc,
		JobShipment,
		PreBlast,
		Destination,
		Notes,
		HashValue
	FROM cds.ExpandedMaterialPlanner src
	WHERE src.PlannerId NOT IN (
		SELECT PlannerId FROM cds.MaterialPlannerSnapshot
	);

	-- [5] delete items no longer in cds.MaterialPlanner
	UPDATE cds.MaterialPlannerSnapshot
	SET
		ModifiedDateTime  = GETDATE(),
		ScheduledBurnDate = NULL,
		Priority          = NULL,
		IsActive          = 0
	WHERE IsActive = 1
	AND PlannerId NOT IN (
		SELECT Id FROM cds.MaterialPlanner
	)

	-- [6] return results
	SELECT
		id,
		modifiedDateTime,
		requestType,
		programName,
		plant,
		bay,
		MachineName AS machine,
		ScheduledBurnDate AS fabBurnDate,
		priority,
		materialMaster,
		batch,
		weight,
		thickness,
		width,
		length,
		CASE
			WHEN Weight IS NULL THEN ''
			WHEN Weight < 50000 THEN '2XL'
			WHEN Weight < 70000 THEN '3XL'
			WHEN Weight < 100000 THEN '4XL'
			ELSE 'OVERWEIGHT'
		END AS TrailerType,
		SLoc,
		jobShipment,
		preblast,
		destination,
		notes
	FROM cds.MaterialPlannerSnapshot
	WHERE ModifiedDateTime > ISNULL(@afterDateTime, '1900-01-01')
	ORDER BY RequestType, Plant, Bay, Priority;
END;
GO


CREATE OR ALTER PROCEDURE inv.GetMaterialPlannerList
	@afterDateTime DATETIME = NULL
AS
BEGIN
	-- This is the procedure that Boomi calls, so we'll just redirect it for now
	EXEC cds.SyncMaterialPlannerSnapshot
END;
GO

GRANT EXECUTE ON SCHEMA::cds TO SNUser;
GO
