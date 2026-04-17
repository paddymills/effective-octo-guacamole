
USE SNInterDev;
GO


CREATE OR ALTER PROCEDURE inv.PreBatchListingUpload
AS
BEGIN
	-- Called before the batches are pushed
	-- Every push will be the entire SAP inventory, so the table is cleared
	-- This could potentially be an issue if inv.UploadBatch fails, leaving
	-- 	the table empty, but we will take that risk for simplicity.

	-- log call
	INSERT INTO log.BatchUpload (Description)
	VALUES ('pre-upload call');

	-- clear table
	DELETE FROM inv.Batches;
END;
GO
CREATE OR ALTER PROCEDURE inv.PostBatchListingUpload
AS
BEGIN
	-- Called after the batches are pushed
	-- Every push will be the entire SAP inventory, so the table is cleared
	-- This could potentially be an issue if inv.UploadBatch fails, leaving
	-- 	the table empty, but we will take that risk for simplicity.

	-- log call
	INSERT INTO log.BatchUpload (Description)
	VALUES ('post-upload call');

	-- remove items that were not pushed
	DELETE FROM inv.Batches
	WHERE UpdateControlBit = 1;

	-- reset stale state so that the next push will remove
	-- anything that SAP does not push
	UPDATE inv.Batches
	SET UpdateControlBit = 1;
END;
GO

CREATE OR ALTER PROCEDURE inv.UploadBatch
	@batch VARCHAR(10),
	@sheet_type VARCHAR(64),	-- New Sheet, NonStandard Size, Remnant
	@sheet_name VARCHAR(50),
	@material_master VARCHAR(50),
	@plant VARCHAR(4),
	@sloc VARCHAR(4)
AS
BEGIN
	-- log call
	INSERT INTO log.BatchUpload (Batch, SheetType, SheetName, MaterialMaster, Plant, SLoc)
	VALUES (@batch, @sheet_type, @sheet_name, @material_master, @plant, @sloc);

	-- update cds.MaterialPlanner if
	-- - this batch applies to a nest on the material planner
	-- - there is a storage location change (need to do this before the batch update)
	UPDATE cds.MaterialPlanner
	SET ModifiedDateTime=CURRENT_TIMESTAMP
	WHERE Id in (
		SELECT mp.Id
		FROM cds.MaterialPlanner mp
		INNER JOIN sap.ProgramStatus ps
			ON ps.ProgramName=mp.ProgramName
		INNER JOIN oys.ChildPlate cp
			ON cp.ProgramGUID=ps.ProgramGUID
		INNER JOIN inv.Batches b
			ON b.SheetName=cp.PlateName
		WHERE b.SheetName = @sheet_name
		AND b.SLoc != @sloc
		AND b.Batch = @batch
	);

	-- insert values
	UPDATE inv.Batches
	SET
		SheetType=@sheet_type,
		SheetName=@sheet_name,
		MaterialMaster=@material_master,
		Plant=@plant,
		SLoc=@sloc,
		UpdateControlBit=0
	WHERE Batch=@batch;

	IF @@ROWCOUNT < 1
	BEGIN
		INSERT INTO inv.Batches (Batch, SheetType, SheetName, MaterialMaster, Plant, SLoc)
		VALUES (@batch, @sheet_type, @sheet_name, @material_master, @plant, @sloc);
	END;
END;
GO
