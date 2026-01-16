import os
import pyodbc
import time
import xlwings

import datetime as dt


# SQL Server credentials
SQL_USER = os.environ["SNDB_USER"]
SQL_PASSWORD = os.environ["SNDB_PWD"]
connstr = f"Driver={{SQL Server}};Server=HSSSNData;Database=SNInterPrd;UID={SQL_USER};PWD={SQL_PASSWORD}"
outfile = r"C:\Users\PMiller1\OneDrive - high.net\HighSteel-OYS\SAP-DemandAndInventoryQueues.xlsx"

get_demand = """
select
    Id, SapEventId, SapPartName, WorkOrder, PartName, Qty, Matl,
    OnHold, State, Dwg, Codegen, Job, Shipment,
    Op1, Op2, Op3, Mark, RawMaterialMaster, DueDate
from sap.DemandQueue
where Id > ?
order by Id asc
"""
get_inventory = """
select
    Id, SapEventId, SheetName, SheetType, Qty, Matl,
    Thk, Width, Length, MaterialMaster,
    Notes1, Notes2, Notes3, Notes4
from sap.InventoryQueue
where Id > ?
order by Id asc
"""

class QueuePoller:
    def __init__(self):
        wb = xlwings.Book(outfile)
        self.demand = wb.sheets["DemandQueue"].range("A2:S2").expand("down").value or []
        self.inventory = wb.sheets["InventoryQueue"].range("A2:N2").expand("down").value or []
        wb.save()
        wb.close()

        try:
            if len(xlwings.books) == 0:
                xlwings.apps.active.quit()
        except:
            pass

        self.demand_id = max([row[0] for row in self.demand], default=0)
        self.inventory_id = max([row[0] for row in self.inventory], default=0)

    def poll_db(self):
        new_records = 0

        # Connect to database
        conn = pyodbc.connect(connstr)

        try:
            for _ in range(30):  # Poll 10 times
                cursor = conn.cursor()
                cursor.execute(get_demand, self.demand_id)
                for row in cursor.fetchall():
                    self.demand.append(list(row))
                    new_records += 1
                    self.demand_id = row.Id  # Update last processed ID

                cursor.execute(get_inventory, self.inventory_id)
                for row in cursor.fetchall():
                    self.inventory.append(list(row))
                    new_records += 1
                    self.inventory_id = row.Id  # Update last processed ID

                time.sleep(1)
        finally:
            conn.close()

        if new_records > 0:
            print(f"Fetched {new_records} new records from queues")
            wb = xlwings.Book(outfile)
            try:
                wb.sheets["DemandQueue"].range("A2").value = self.demand
            except Exception as e:
                print(f"Failed to write DemandQueue data to Excel ({e})")

            try:
                wb.sheets["InventoryQueue"].range("A2").value = self.inventory
            except Exception as e:
                print(f"Failed to write InventoryQueue data to Excel ({e})")

            wb.save()
            wb.close()

            try:
                if len(xlwings.books) == 0:
                    xlwings.apps.active.quit()
            except:
                pass
            
if __name__ == "__main__":
    poller = QueuePoller()

    ct = dt.datetime.now()
    next_5_minute = (ct.replace(minute=0, second=0, microsecond=0))
    while next_5_minute <= ct:
        next_5_minute += dt.timedelta(minutes=5)
    next_5_minute -= dt.timedelta(seconds=5)  # small buffer

    while True:
        sleep_seconds = (next_5_minute - dt.datetime.now()).total_seconds()
        print(f"wake me at {next_5_minute.strftime('%H:%M:%S')}...", end="", flush=True)
        time.sleep(sleep_seconds)

        print(f"Polling queues at {dt.datetime.now().strftime('%H:%M:%S')}")
        poller.poll_db()

        next_5_minute += dt.timedelta(minutes=5)
