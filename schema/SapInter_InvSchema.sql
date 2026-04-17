
USE SNInterDev;
GO

-- Inventory schema
CREATE SCHEMA inv;
GO

CREATE TABLE inv.Batches (
	Batch VARCHAR(10) PRIMARY KEY,
	SheetType VARCHAR(64),	-- New Sheet, NonStandard Size, Remnant
	SheetName VARCHAR(50),
	MaterialMaster VARCHAR(50),
	Plant VARCHAR(4),
	SLoc VARCHAR(4),
	UpdateControlBit BIT
);
GO
