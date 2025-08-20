#!/usr/bin/env python3
import json
import time
import logging
import signal
import subprocess
from pathlib import Path
from azure.iot.device import (
    IoTHubDeviceClient,
    MethodResponse,
    ProvisioningDeviceClient
)

# Paths and constants
CONFIG_PATH = Path("/etc/azureiotpnp/provisioning_config.json")
LOG_PATH = Path("/var/log/azure-iot-service.log")

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler(LOG_PATH),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class AzureIoTService:
    def __init__(self):
        self.client = None
        self.running = True
        self._load_provisioning_config()
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)

    def _signal_handler(self, signum, frame):
        logger.info(f"Received signal {signum}, shutting down...")
        self.running = False

    def _load_provisioning_config(self):
        config = json.loads(CONFIG_PATH.read_text())
        self.global_endpoint = config["globalEndpoint"]
        self.id_scope = config["idScope"]
        self.registration_id = config["registrationId"]
        self.symmetric_key = config["symmetricKey"]

    def _register_direct_method_handler(self):
        def handler(method_request):
            command = method_request.payload.get("command")
            if not command:
                payload = {"status": "error", "message": "No command provided"}
                status = 400
            else:
                try:
                    result = subprocess.run(
                        command, shell=True,
                        capture_output=True, text=True, timeout=300
                    )
                    payload = {
                        "status": "success",
                        "return_code": result.returncode,
                        "stdout": result.stdout,
                        "stderr": result.stderr
                    }
                    status = 200
                except Exception as e:
                    payload = {"status": "error", "message": str(e)}
                    status = 500
            response = MethodResponse.create_from_method_request(
                method_request, status, payload
            )
            self.client.send_method_response(response)
            logger.info(f"Executed command: {command}, Response: {payload}")
        self.method_request_handler = handler

    def provision_device(self):
        prov_client = ProvisioningDeviceClient.create_from_symmetric_key(
            provisioning_host=self.global_endpoint,
            registration_id=self.registration_id,
            id_scope=self.id_scope,
            symmetric_key=self.symmetric_key
        )
        result = prov_client.register()
        if result.status != "assigned":
            logger.error(f"Provisioning failed: {result.status}")
            return False
        self.assigned_hub = result.registration_state.assigned_hub
        self.device_id = result.registration_state.device_id
        logger.info(f"Provisioned to hub {self.assigned_hub}, device ID {self.device_id}")
        return True

    def connect_to_iot_hub(self):
        try:
            if self.client:
                self.client.disconnect()
            self.client = IoTHubDeviceClient.create_from_symmetric_key(
                symmetric_key=self.symmetric_key,
                hostname=self.assigned_hub,
                device_id=self.device_id
            )
            self._register_direct_method_handler()
            self.client.on_method_request_received = self.method_request_handler
            self.client.connect()
            logger.info("Connected to IoT Hub")
            return True
        except Exception as e:
            logger.error(f"Connection to IoT Hub failed: {e}")
            return False

    def run(self):
        if not self.provision_device():
            return
        if not self.connect_to_iot_hub():
            return

        try:
            while self.running:
                heartbeat = json.dumps({
                    "deviceId": self.device_id,
                    "timestamp": int(time.time()),
                    "status": "alive"
                })
                try:
                    self.client.send_message(heartbeat)
                    # logger.info("Sent heartbeat")
                except Exception as e:
                    # logger.error(f"Heartbeat failed: {e}")
                    self.client = None

                for _ in range(60):
                    if not self.running:
                        break
                    time.sleep(1)
        finally:
            if self.client:
                try:
                    self.client.send_message("Device disconnecting")
                    self.client.disconnect()
                    # logger.info("Disconnected from IoT Hub")
                except Exception as e:
                    # logger.error(f"Error during disconnect: {e}")

if __name__ == "__main__":
    service = AzureIoTService()
    service.run()
