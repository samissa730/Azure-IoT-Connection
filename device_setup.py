#!/usr/bin/env python3
"""
Device Setup Script for Nexus Locate IoT
Generates device-specific configuration from group key and user inputs
"""

import json
import hmac
import hashlib
import base64
import subprocess
from pathlib import Path

CONFIG_PATH = Path("/etc/azureiotpnp/provisioning_config.json")

def get_device_serial():
    """Get device serial number"""
    try:
        result = subprocess.run(['cat', '/proc/cpuinfo'], capture_output=True, text=True)
        for line in result.stdout.split('\n'):
            if line.startswith('Serial'):
                serial = line.split(':')[1].strip().lstrip('0')
                return serial if serial else "unknown"
    except:
        pass
    return "unknown"

def compute_derived_key(group_key, registration_id):
    """Compute device-specific key from group key and registration ID"""
    try:
        key_bytes = base64.b64decode(group_key)
        message = registration_id.encode('utf-8')
        signed_hmac = hmac.new(key_bytes, message, hashlib.sha256)
        derived_key = base64.b64encode(signed_hmac.digest()).decode('utf-8')
        return derived_key
    except Exception as e:
        print(f"Error computing derived key: {e}")
        return None

def get_user_input():
    """Get configuration inputs from user"""
    print("=" * 60)
    print("Nexus Locate IoT Device Setup")
    print("=" * 60)
    
    # Show device serial number
    serial = get_device_serial()
    print(f"\nDevice Serial Number: {serial}")
    print(f"Suggested Device ID: nexus-{serial}")
    
    # Get inputs
    print("\nPlease provide the following information:")
    
    group_key = input("\n1. Group Primary Key (from Azure Portal): ").strip()
    if not group_key:
        print("Error: Group key is required!")
        return None
    
    default_device_id = f"nexus-{serial}"
    device_id = input(f"\n2. Device ID [{default_device_id}]: ").strip()
    if not device_id:
        device_id = default_device_id
    
    id_scope = input("\n3. DPS ID Scope (from Azure Portal): ").strip()
    if not id_scope:
        print("Error: ID Scope is required!")
        return None
    
    site_name = input("\n4. Site Name (e.g., Warehouse_A): ").strip()
    if not site_name:
        print("Error: Site Name is required!")
        return None
    
    truck_number = input("\n5. Truck Number (e.g., Truck_001): ").strip()
    if not truck_number:
        print("Error: Truck Number is required!")
        return None
    
    return {
        'group_key': group_key,
        'device_id': device_id,
        'id_scope': id_scope,
        'site_name': site_name,
        'truck_number': truck_number,
        'serial': serial
    }

def save_configuration(inputs):
    """Generate and save device configuration"""
    # Generate device-specific symmetric key
    derived_key = compute_derived_key(inputs['group_key'], inputs['device_id'])
    if not derived_key:
        return False
    
    # Create configuration
    config = {
        "globalEndpoint": "global.azure-devices-provisioning.net",
        "idScope": inputs['id_scope'],
        "group_key": inputs['group_key'],
        "registrationId": inputs['device_id'],
        "symmetricKey": derived_key,
        "tags": {
            "nexusLocate": {
                "siteName": inputs['site_name'],
                "truckNumber": inputs['truck_number'],
                "deviceSerial": inputs['serial']
            }
        }
    }
    
    try:
        # Create directory if it doesn't exist
        CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
        
        # Save configuration
        CONFIG_PATH.write_text(json.dumps(config, indent=2))
        
        # Set proper permissions
        subprocess.run(['sudo', 'chmod', '600', str(CONFIG_PATH)], check=True)
        
        return True
    except Exception as e:
        print(f"Error saving configuration: {e}")
        return False

def main():
    # Check if already configured
    if CONFIG_PATH.exists():
        print("Device is already configured!")
        response = input("Do you want to reconfigure? (yes/no): ").strip().lower()
        if response not in ['yes', 'y']:
            print("Setup cancelled.")
            return
    
    # Get user inputs
    inputs = get_user_input()
    if not inputs:
        print("Setup failed due to missing inputs.")
        return
    
    # Show summary
    print("\n" + "=" * 60)
    print("Configuration Summary:")
    print("=" * 60)
    print(f"Device ID: {inputs['device_id']}")
    print(f"ID Scope: {inputs['id_scope']}")
    print(f"Site Name: {inputs['site_name']}")
    print(f"Truck Number: {inputs['truck_number']}")
    print(f"Device Serial: {inputs['serial']}")
    print("=" * 60)
    
    confirm = input("\nSave this configuration? (yes/no): ").strip().lower()
    if confirm not in ['yes', 'y']:
        print("Setup cancelled.")
        return
    
    # Save configuration
    if save_configuration(inputs):
        print(f"\n✓ Configuration saved to {CONFIG_PATH}")
        print("✓ Device setup completed successfully!")
        print("\nNext steps:")
        print("1. Install and start the IoT service")
        print("2. The device will automatically connect to Azure IoT Hub")
    else:
        print("\n✗ Failed to save configuration")

if __name__ == "__main__":
    from datetime import datetime
    main()
