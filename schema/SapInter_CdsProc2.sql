
USE SNInterDev;
GO

-- TODO: remove once new version is stabilized
CREATE OR ALTER PROCEDURE inv.GetMaterialPlannerListOld
	@afterDateTime DATETIME = NULL
AS
BEGIN
	EXEC cds.CleanMaterialPlanner;

	-- get planner data for SharePoint
	WITH
		Jobs AS (
			SELECT
				ProgramName,
				STRING_AGG(JobShipment, ',') AS Jobs
			FROM (
				SELECT DISTINCT
					ProgramName,
					CONCAT(ChildPart.Job, '-', ChildPart.Shipment) AS JobShipment
				FROM cds.NestChildPlates
				INNER JOIN oys.ChildPart
					ON ChildPart.ChildPlateGUID=NestChildPlates.ChildPlateGUID
				WHERE ISNULL(ChildPart.Job, '') != ''
			) AS js
			GROUP BY ProgramName
		),
		HaulIn AS (
			SELECT
				planner.Id,
				planner.ModifiedDateTime,
				planner.RequestType,
				planner.ProgramName,
				prog.MachineName,
				ISNULL(planner.ScheduledBurnDate, '') AS ScheduledBurnDate,	-- NULL if nest needs removed
				'<removed>' AS Priority, -- old: planner.Priority
				planner.PreBlast,
				ISNULL(Jobs.Jobs,'') AS JobShipment,
				ChildPlate.PlateName AS SheetName,
				planner.Notes
			FROM cds.MaterialPlanner planner
			INNER JOIN sap.ActivePrograms prog
				ON prog.ProgramName=planner.ProgramName
			INNER JOIN oys.ChildPlate
				ON ChildPlate.ProgramGUID=prog.ProgramGUID
				AND ChildPlate.PlateNumber=planner.SheetIndex
			LEFT JOIN Jobs
				ON Jobs.ProgramName=planner.ProgramName

			WHERE RequestType = 'Haul In'
		),
		HaulOut AS (
			SELECT
				planner.Id,
				ModifiedDateTime,
				RequestType,
				Machines.MachineName,
				planner.SheetName,

				Destination
			FROM cds.MaterialPlanner planner
			INNER JOIN inv.Batches
				ON Batches.SheetName=planner.SheetName
			INNER JOIN cds.Machines
				ON Machines.SLoc=Batches.SLoc

			WHERE RequestType = 'Haul Out'
		),
		HaulList AS (
			SELECT
				Id,
				ModifiedDateTime,
				RequestType,
				ProgramName,
				MachineName,
				ScheduledBurnDate,
				Priority,
				JobShipment,
				SheetName,
				IIF(PreBlast=1, 'Yes', 'No') AS PreBlast,
				'' AS Destination,
				Notes

			FROM HaulIn

			UNION

			SELECT
				Id,
				ModifiedDateTime,
				RequestType,
				'' AS ProgramName,
				MachineName,
				'' AS ScheduledBurnDate,
				'' AS Priority,
				'' AS JobShipment,
				SheetName,
				'' AS PreBlast,
				Destination,
				'' AS Notes

			FROM HaulOut
		)
	SELECT
		HaulList.id,
		modifiedDateTime,
		requestType,
		programName,
		plant,
		bay,
		HaulList.MachineName AS machine,
		ScheduledBurnDate AS fabBurnDate,
		priority,
		Stock.materialMaster,
		CASE
			WHEN Stock.SheetName != Stock.MaterialMaster
				THEN (
					SELECT TOP 1 Batch
					FROM inv.Batches
					WHERE Batches.SheetName=Stock.SheetName
				)
			ELSE ''
		END AS batch,
		ROUND(Stock.Weight + 100, -2) AS weight, -- round up to the nearest 100 lbs
		Stock.thickness,
		Stock.width,
		Stock.length,
		CASE
			WHEN Stock.Weight < 50000 THEN '2XL'
			WHEN Stock.Weight < 70000 THEN '3XL'
			WHEN Stock.Weight < 100000 THEN '4XL'
			ELSE 'OVERWEIGHT'
		END AS trailerType,
		ISNULL(SLocMap.Sloc, '') AS SLoc,
		jobShipment,
		preblast,
		destination,
		notes
	FROM HaulList
	LEFT JOIN cds.Machines
		ON Machines.MachineName=HaulList.MachineName
	LEFT JOIN inv.SlocMap
		ON SLocMap.SheetName=HaulList.SheetName
	LEFT JOIN inv.StockWeights Stock
		ON Stock.SheetName=HaulList.SheetName
	WHERE ModifiedDateTime > ISNULL(@afterDateTime, CAST(0 AS DateTime))
	ORDER BY HaulList.Id;

	-- remove deletions
	DELETE FROM cds.MaterialPlanner
	WHERE RequestType = 'Haul In'
	AND ScheduledBurnDate IS NULL;
END;
GO


CREATE OR ALTER PROCEDURE cds.ScheduleNest
	@program_name VARCHAR(50),
	@priority INT = NULL,
	@date DATE,
	@shift INT = 1,
	@preblast BIT = 0,
	@username VARCHAR(50) = NULL,
	@notes VARCHAR(1000) = NULL
AS
BEGIN
	-- find if it is an add or a modification
	-- log change
	-- create/update entry
	IF EXISTS (SELECT 1 FROM cds.MaterialPlanner WHERE ProgramName=@program_name)
	BEGIN
		INSERT INTO log.MaterialPlanner (
			Action,ProgramName,Priority,ScheduledBurnDate,Shift,PreBlast,ScheduledBy,Notes
		)
		VALUES (
			'MOVE', @program_name, @priority, @date, @shift, @preblast, ISNULL(@username, CURRENT_USER), @notes
		);

		UPDATE cds.MaterialPlanner
		SET
			ModifiedDateTime=CURRENT_TIMESTAMP,
			Priority=@priority,
			ScheduledBurnDate=@date,
			Shift=ISNULL(@shift, 1),
			PreBlast=@preblast,
			Notes=ISNULL(@notes, '')
		WHERE ProgramName=@program_name;
	END

	ELSE
	BEGIN
		INSERT INTO log.MaterialPlanner (
			Action, ProgramName, Priority, ScheduledBurnDate, Shift, PreBlast, ScheduledBy
		)
		VALUES (
			'ADD', @program_name, @priority, @date, @shift, @preblast, ISNULL(@username, CURRENT_USER)
		);

		INSERT INTO cds.MaterialPlanner (
			RequestType, ProgramName, SheetIndex, Priority, ScheduledBurnDate, Shift, PreBlast, Notes
		)
		SELECT
			'Haul In',
			@program_name,
			ChildPlate.PlateNumber,
			@priority,
			@date,
			@shift,
			@preblast,
			@notes
		FROM sap.ActivePrograms
		INNER JOIN oys.ChildPlate
			ON ChildPlate.ProgramGUID=ActivePrograms.ProgramGUID
		WHERE ActivePrograms.ProgramName=@program_name;
	END
END;
GO

CREATE OR ALTER PROCEDURE cds.DeleteScheduledNest
	@program_name VARCHAR(50),
	@username VARCHAR(50)
AS
BEGIN
	INSERT INTO log.MaterialPlanner (Action, ProgramName, ScheduledBy)
	VALUES ('DELETE', @program_name, @username);

	--DELETE FROM cds.MaterialPlanner
	--WHERE ProgramName = @program_name;
	UPDATE cds.MaterialPlanner
	SET
		Priority=0,
		ScheduledBurnDate=NULL
	WHERE ProgramName = @program_name;
END;
GO

CREATE OR ALTER PROCEDURE cds.AddToHaulOut
	@sheet_name VARCHAR(50),
	@destination VARCHAR(16),
	@username VARCHAR(50)
AS
BEGIN
	INSERT INTO log.MaterialPlanner (Action, SheetName, Destination, ScheduledBy)
	VALUES ('ADD', @sheet_name, @destination, @username);

	INSERT INTO cds.MaterialPlanner (
		RequestType, SheetName, Destination
	)
	VALUES ('Haul Out', @sheet_name, ISNULL(@destination, 'Yard'))
END;
GO

CREATE OR ALTER PROCEDURE cds.DeleteHaulOut
	@sheet_name VARCHAR(50),
	@username VARCHAR(50)
AS
BEGIN
	INSERT INTO log.MaterialPlanner (Action, SheetName, ScheduledBy)
	VALUES ('DELETE', @sheet_name, @username);

	DELETE FROM cds.MaterialPlanner
	WHERE SheetName = @sheet_name;
END;
GO

CREATE OR ALTER PROCEDURE cds.SetNotes
	@program_name VARCHAR(50),
	@notes VARCHAR(1000),
	@username VARCHAR(50)
AS
BEGIN
	INSERT INTO log.MaterialPlanner (Action, ProgramName, ScheduledBy, Notes)
	VALUES ('NOTES', @program_name, @username, @notes);

	UPDATE cds.MaterialPlanner
	SET
		Notes = @notes
	WHERE ProgramName = @program_name;
END;
GO


CREATE OR ALTER PROCEDURE cds.SetPreBlast
	@program_name VARCHAR(50),
	@preblast BIT,
	@username VARCHAR(50)
AS
BEGIN
	INSERT INTO log.MaterialPlanner (Action, ProgramName, ScheduledBy, PreBlast)
	VALUES ('NOTES', @program_name, @username, @preblast);

	UPDATE cds.MaterialPlanner
	SET
		PreBlast = @preblast
	WHERE ProgramName = @program_name;
END;
GO
