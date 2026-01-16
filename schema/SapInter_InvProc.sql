
USE SNInterDev;
GO

CREATE OR ALTER PROCEDURE inv.PreBatchListingUpload
AS
BEGIN
	-- Called before the batches are pushed
	-- Every push will be the entire SAP inventory, so the table is cleared
	-- This could potentially be an issue if inv.UploadBatch fails, leaving
	-- 	the table empty, but we will take that risk for simplicity.
	DELETE FROM inv.Batches;
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
	-- insert values
	INSERT INTO inv.Batches (Batch, SheetType, SheetName, MaterialMaster, Plant, SLoc)
	VALUES (@batch, @sheet_type, @sheet_name, @material_master, @plant, @sloc);
END;
GO
