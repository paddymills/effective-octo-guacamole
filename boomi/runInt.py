
# /// script
# dependencies = [
#   "requests",
# ]
# ///

import requests
from datetime import datetime
import time

url = "https://api.boomi.com/api/rest/v1/highcompanyllc-75KB3N/ExecutionRequest"

processIds = [
    "6a7ab355-55c0-40a5-b005-c9f22688a5e3",
    "7dbec98c-2f1e-43f0-8a84-24b93b5780b7",
    "4b751714-2a36-4536-958d-f15b85092a47",
    "66482d03-0edd-4207-ac4b-f663e45c03e3"
]

def payload(processId):
    return {
        "atomId": "e13c6761-6986-45e3-870b-8bd3e73946f1",
        "processId": processId,
    }

headers = {
    "content-type": "application/json",
    "accept": "application/json"
}


while 1:
    print("[{datetime}] Executing...".format(datetime=datetime.now()))
    responses = [requests.post(
        url,
        json=payload(p),
        headers=headers,
        auth=('BOOMI_TOKEN.boomiprocess@high.net', '1095f0bf-315d-4c0c-84da-ee88438f6dbe')
    ) for p in processIds]

    for i, response in enumerate(responses, start=1):
        print(f"\t[{datetime.now()}] Interface {i}: {response.status_code}")

    delay = 60  # 1h delay after 6pm
    if 6 < datetime.now().hour < 18:
        # Wait for 10 minutes during working hours
        delay = 10
    time.sleep(delay * 60)
