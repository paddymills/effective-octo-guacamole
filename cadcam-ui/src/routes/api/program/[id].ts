import { APIEvent } from "@solidjs/start/server";
import { DatabaseService } from "~/lib/database";
import { handleApiRequest } from "~/lib/api-handler";

export async function POST(event: APIEvent): Promise<Response> {
  return handleApiRequest(async () => {
    const db = new DatabaseService();
    const id = event.params.id;
    
    if (!id || isNaN(Number(id))) {
      throw new Error('Invalid archive packet ID');
    }
    
    await db.execute('sap.ReleaseProgram', {'archive_packet_id': id});
    
    return { success: true };
  }, `Program ${event.params.id} released successfully`);
}

export async function DELETE(event: APIEvent): Promise<Response> {
  return handleApiRequest(async () => {
    const db = new DatabaseService();
    const id = event.params.id;
    
    if (!id || isNaN(Number(id))) {
      throw new Error('Invalid archive packet ID');
    }
    
    await db.execute('sap.DeleteProgram', {'archive_packet_id': id, 'sap_event_id': 'delete_program'});
    
    return { success: true };
  }, `Program ${event.params.id} deleted successfully`);
}
