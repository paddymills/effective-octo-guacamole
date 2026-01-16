import os
import pyodbc


# SQL Server credentials
SQL_USER = os.environ["SNDB_USER"]
SQL_PASSWORD = os.environ["SNDB_PWD"]

# Connect to databases
source_conn = pyodbc.connect(
    f"Driver={{SQL Server}};Server=HIISQLSERV6;Database=SNDBaseDev;UID={SQL_USER};PWD={SQL_PASSWORD}"
)
dest_conn = pyodbc.connect(
    f"Driver={{SQL Server}};Server=HIISQLSERV5;Database=SNDBasePrd;UID={SQL_USER};PWD={SQL_PASSWORD}"
)

try:
    # Get IDs to move
    source_cursor = source_conn.cursor()
    source_cursor.execute("SELECT AutoInc FROM dbo.TransAct WHERE District < 99")
    ids_to_move = [row[0] for row in source_cursor.fetchall()]
    print(f"Found {len(ids_to_move)} records to move")

    # Delete error records from remote
    dest_cursor = dest_conn.cursor()
    dest_cursor.execute(
        "DELETE FROM dbo.TransAct WHERE District IN (3, 4) AND ErrorTag = 1"
    )
    dest_conn.commit()
    print(f"Deleted {dest_cursor.rowcount} error records from remote")

    # Get records from source database
    source_cursor.execute(
        f"""
        SELECT
            TransType, District, TransID,
            OrderNo, ItemName, OnHold, Qty, Material, Customer, DwgNumber,
            Thickness, Width, Length, FileName, PrimeCode, BinNumber, Remark,
            ItemData1, ItemData2, ItemData3, ItemData4, ItemData5, ItemData6,
            ItemData7, ItemData8, ItemData9, ItemData10, ItemData11, ItemData12,
            ItemData13, ItemData14, ItemData15, ItemData16, ItemData17, ItemData18,
            ProgramName, ProgramRepeat
        FROM dbo.TransAct
        WHERE District < 99
    """
    )
    records = list(source_cursor.fetchall())

    if not records:
        print("no SimTrans records to move")
        exit()

    # Insert into destination database
    dest_cursor.executemany(
        """
        INSERT INTO dbo.TransAct (
            TransType, District, TransID,
            OrderNo, ItemName, OnHold, Qty, Material, Customer, DwgNumber,
            Thickness, Width, Length, FileName, PrimeCode, BinNumber, Remark,
            ItemData1, ItemData2, ItemData3, ItemData4, ItemData5, ItemData6,
            ItemData7, ItemData8, ItemData9, ItemData10, ItemData11, ItemData12,
            ItemData13, ItemData14, ItemData15, ItemData16, ItemData17, ItemData18,
            ProgramName, ProgramRepeat
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """,
        records,
    )
    dest_conn.commit()
    print(f"Inserted {dest_cursor.rowcount} records into destination")

    # Delete from source database
    source_cursor.execute(f"DELETE FROM dbo.TransAct WHERE District < 99")
    source_conn.commit()
    print(f"Deleted {source_cursor.rowcount} records from source")

    # Update error tags
    dest_cursor.execute("UPDATE dbo.TransAct SET ErrorTag = 0")
    dest_conn.commit()
    print(f"Updated {dest_cursor.rowcount} error tags")

    # Show results
    dest_cursor.execute("SELECT * FROM dbo.TransAct")
    rows = dest_cursor.fetchall()
    print(f"\nFinal record count: {len(rows)}")

    print("Migration completed successfully!")

except Exception as e:
    print(f"Error: {e}")
    source_conn.rollback()
    dest_conn.rollback()
    raise

finally:
    source_conn.close()
    dest_conn.close()
