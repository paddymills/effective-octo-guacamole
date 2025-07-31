
USE SNInterDev;
GO

CREATE OR ALTER PROCEDURE cds.GetActiveNests
	@job VARCHAR(50) NULL,
	@shipment VARCHAR(50) NULL
AS
BEGIN
	-- TODO: rebuild these into a view
	SET @job = NULLIF(@job, '');
	SET @shipment = NULLIF(@shipment, '');

	WITH ProgramParts AS (
		SELECT
			ProgramName,
			STRING_AGG(
				REPLACE(ParentPart.SNPartName, ISNULL(@job,'<notfound>')+'_', ''), ', '
			) WITHIN GROUP (ORDER BY ParentPart.SNPartName) AS Parts
		FROM sap.ProgramStatus
		INNER JOIN oys.ParentPart
			ON ParentPart.ProgramGUID=ProgramStatus.ProgramGUID
		WHERE ParentPart.ParentPartGUID IN (
			SELECT ParentPartGUID
			FROM oys.ChildPart
			WHERE ChildPart.Job LIKE ISNULL(@job,'%')
			AND ChildPart.Shipment LIKE ISNULL(@shipment,'%')
		)
		AND SigmanestStatus IN ('Created', 'Released')
		GROUP BY ProgramName
	)
		SELECT
			ProgramParts.ProgramName,
			Program.MachineName,
			SigmanestStatus AS ProgramStatus,
			CASE
				WHEN Program.NestType = 'Slab'
					THEN ParentPlate.PlateName
				ELSE (
					SELECT TOP 1 MaterialMaster
					FROM oys.ChildPlate
					WHERE ChildPlate.ProgramGUID=Program.ProgramGUID
				)
			END AS MaterialMaster,
			ParentPlate.Material AS Grade,
			ParentPlate.Thickness,
			Parts,
			DatePrinted
		FROM ProgramParts
		LEFT JOIN cds.ShopNestData
			ON ProgramParts.ProgramName=ShopNestData.ProgramName
		INNER JOIN sap.ProgramStatus
			ON ProgramParts.ProgramName=ProgramStatus.ProgramName
		INNER JOIN oys.Program
			ON Program.ProgramGUID=ProgramStatus.ProgramGUID
		INNER JOIN oys.ParentPlate
			ON ParentPlate.ProgramGUID=ProgramStatus.ProgramGUID;
END;
GO
CREATE OR ALTER PROCEDURE cds.GetCompleteNests
	@job VARCHAR(50) NULL,
	@shipment VARCHAR(50) NULL
AS
BEGIN
	-- TODO: rebuild these into a view
	SET @job = NULLIF(@job, '');
	SET @shipment = NULLIF(@shipment, '');

	WITH ProgramParts AS (
		SELECT
			ProgramName,
			STRING_AGG(
				REPLACE(ParentPart.SNPartName, ISNULL(@job,'')+'_', ''), ','
			) WITHIN GROUP (ORDER BY ParentPart.SNPartName) AS Parts
		FROM sap.ProgramStatus
		INNER JOIN oys.ParentPart
			ON ParentPart.ProgramGUID=ProgramStatus.ProgramGUID
		WHERE ParentPart.ParentPartGUID IN (
			SELECT ParentPartGUID
			FROM oys.ChildPart
			WHERE ChildPart.Job LIKE ISNULL(@job,'%')
			AND ChildPart.Shipment LIKE ISNULL(@shipment,'%')
		)
		AND SigmanestStatus = 'Updated'
		GROUP BY ProgramName
	)
		SELECT
			ProgramParts.ProgramName,
			Program.MachineName,
			SigmanestStatus AS ProgramStatus,
			CASE
				WHEN Program.NestType = 'Slab'
					THEN ParentPlate.PlateName
				ELSE (
					SELECT TOP 1 MaterialMaster
					FROM oys.ChildPlate
					WHERE ChildPlate.ProgramGUID=Program.ProgramGUID
				)
			END AS MaterialMaster,
			ParentPlate.Material AS Grade,
			ParentPlate.Thickness,
			Parts,
			DatePrinted
		FROM ProgramParts
		LEFT JOIN cds.ShopNestData
			ON ProgramParts.ProgramName=ShopNestData.ProgramName
		INNER JOIN sap.ProgramStatus
			ON ProgramParts.ProgramName=ProgramStatus.ProgramName
		INNER JOIN oys.Program
			ON Program.ProgramGUID=ProgramStatus.ProgramGUID
		INNER JOIN oys.ParentPlate
			ON ParentPlate.ProgramGUID=ProgramStatus.ProgramGUID;
END;
GO

CREATE OR ALTER PROCEDURE cds.GetNestParts
	@job VARCHAR(50),
	@shipment INT
AS
BEGIN
	SELECT
		ProgramStatus.ProgramName,
		Program.MachineName,
		SigmanestStatus AS ProgramStatus,
		ChildPlate.MaterialMaster,
		ChildPlate.Material AS Grade,
		ChildPlate.Thickness,
		REPLACE(ChildPart.SNPartName, @job+'_', '') AS PartName,
		ChildPart.QtyProgram AS Qty,
		DatePrinted
	FROM sap.ProgramStatus
	LEFT JOIN cds.ShopNestData
		ON ProgramStatus.ProgramName=ShopNestData.ProgramName
	INNER JOIN oys.Program
		ON Program.ProgramGUID=ProgramStatus.ProgramGUID
	INNER JOIN oys.ChildPlate
		ON ChildPlate.ProgramGUID=ProgramStatus.ProgramGUID
	INNER JOIN oys.ChildPart
		ON ChildPart.ChildPlateGUID=ChildPlate.ChildPlateGUID
	WHERE ChildPart.Job=@job AND ChildPart.Shipment = @shipment;
END;
GO

CREATE OR ALTER PROCEDURE cds.UnmarkNestPrinted
	@nest VARCHAR(50)
AS
BEGIN
	INSERT INTO archive.ShopNestData
	SELECT * FROM cds.ShopNestData
	WHERE ProgramName=@nest;

	DELETE FROM cds.ShopNestData
	WHERE ProgramName=@nest;
END;
GO
CREATE OR ALTER PROCEDURE cds.MarkNestPrinted
	@nest VARCHAR(50),
	@when DATETIME,
	@username VARCHAR(255) = NULL
AS
BEGIN
	-- delete existing
	EXEC cds.UnmarkNestPrinted @nest;
	
	-- insert new
	INSERT INTO cds.ShopNestData (ProgramName, DatePrinted, PrintedBy)
	VALUES (@nest, @when, @username);
END;
GO