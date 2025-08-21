#!/bin/bash

# Test script to verify Azure IoT service setup
# Run this after setup to ensure everything is working correctly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "=========================================="
echo "Azure IoT Service Setup Test"
echo "=========================================="
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

# Test 1: Check if configuration file exists
print_status "Testing configuration file..."
if [[ -f /etc/azureiotpnp/provisioning_config.json ]]; then
    print_success "Configuration file exists"
    
    # Check file permissions
    perms=$(stat -c %a /etc/azureiotpnp/provisioning_config.json)
    if [[ "$perms" == "600" ]]; then
        print_success "Configuration file has correct permissions (600)"
    else
        print_warning "Configuration file permissions are $perms (should be 600)"
    fi
    
    # Validate JSON syntax and structure
    if python3 -m json.tool /etc/azureiotpnp/provisioning_config.json > /dev/null 2>&1; then
        print_success "Configuration file has valid JSON syntax"
        
        # Check for required fields
        if python3 -c "
import json
config = json.load(open('/etc/azureiotpnp/provisioning_config.json'))
required = ['globalEndpoint', 'idScope', 'registrationId', 'symmetricKey', 'tags']
missing = [f for f in required if f not in config]
if missing:
    print('Missing required fields:', missing)
    exit(1)
if 'nexusLocate' not in config.get('tags', {}):
    print('Missing nexusLocate in tags')
    exit(1)
print('Configuration structure is valid')
" 2>/dev/null; then
            print_success "Configuration structure is valid"
        else
            print_warning "Configuration structure may be incomplete"
        fi
    else
        print_error "Configuration file has invalid JSON syntax"
        exit 1
    fi
else
    print_error "Configuration file not found"
    exit 1
fi

# Test 2: Check if service files exist
print_status "Testing service files..."
if [[ -f /opt/azure-iot/iot_service.py ]]; then
    print_success "IoT service script exists"
    
    if [[ -x /opt/azure-iot/iot_service.py ]]; then
        print_success "IoT service script is executable"
    else
        print_warning "IoT service script is not executable"
    fi
else
    print_error "IoT service script not found"
    exit 1
fi

if [[ -f /opt/azure-iot/device_setup.py ]]; then
    print_success "Device setup script exists"
    
    if [[ -x /opt/azure-iot/device_setup.py ]]; then
        print_success "Device setup script is executable"
    else
        print_warning "Device setup script is not executable"
    fi
else
    print_warning "Device setup script not found (may not be critical)"
fi

if [[ -f /etc/systemd/system/azure-iot.service ]]; then
    print_success "Systemd service file exists"
else
    print_error "Systemd service file not found"
    exit 1
fi

# Test 3: Check if service is enabled and running
print_status "Testing service status..."
if systemctl is-enabled azure-iot.service > /dev/null 2>&1; then
    print_success "Service is enabled to start on boot"
else
    print_warning "Service is not enabled to start on boot"
fi

if systemctl is-active azure-iot.service > /dev/null 2>&1; then
    print_success "Service is currently running"
else
    print_warning "Service is not currently running"
fi

# Test 4: Check Python dependencies
print_status "Testing Python dependencies..."
if python3 -c "import azure.iot.device" > /dev/null 2>&1; then
    print_success "Azure IoT Device SDK is installed"
else
    print_error "Azure IoT Device SDK is not installed"
    exit 1
fi

# Test 5: Check log file
print_status "Testing logging setup..."
if [[ -f /var/log/azure-iot-service.log ]]; then
    print_success "Log file exists"
    
    if [[ -w /var/log/azure-iot-service.log ]]; then
        print_success "Log file is writable"
    else
        print_warning "Log file is not writable"
    fi
else
    print_warning "Log file does not exist"
fi

# Test 6: Check network connectivity
print_status "Testing network connectivity..."
if ping -c 1 global.azure-devices-provisioning.net > /dev/null 2>&1; then
    print_success "Can reach Azure DPS endpoint"
else
    print_warning "Cannot reach Azure DPS endpoint (check internet connection)"
fi

# Test 7: Check service logs for errors
print_status "Checking recent service logs..."
if systemctl is-active azure-iot.service > /dev/null 2>&1; then
    recent_logs=$(journalctl -u azure-iot.service --since "5 minutes ago" --no-pager)
    if echo "$recent_logs" | grep -q "error\|Error\|ERROR"; then
        print_warning "Found errors in recent service logs:"
        echo "$recent_logs" | grep -i "error" | tail -5
    else
        print_success "No recent errors found in service logs"
    fi
fi

echo
echo "=========================================="
echo "Test Results Summary"
echo "=========================================="
echo

# Count successes and warnings
success_count=0
warning_count=0
error_count=0

# Run tests again to count results
if [[ -f /etc/azureiotpnp/provisioning_config.json ]]; then ((success_count++)); fi
if [[ -f /opt/azure-iot/iot_service.py ]]; then ((success_count++)); fi
if [[ -f /opt/azure-iot/device_setup.py ]]; then ((success_count++)); else ((warning_count++)); fi
if [[ -f /etc/systemd/system/azure-iot.service ]]; then ((success_count++)); fi
if systemctl is-enabled azure-iot.service > /dev/null 2>&1; then ((success_count++)); else ((warning_count++)); fi
if systemctl is-active azure-iot.service > /dev/null 2>&1; then ((success_count++)); else ((warning_count++)); fi
if python3 -c "import azure.iot.device" > /dev/null 2>&1; then ((success_count++)); else ((error_count++)); fi
if [[ -f /var/log/azure-iot-service.log ]]; then ((success_count++)); else ((warning_count++)); fi
if ping -c 1 global.azure-devices-provisioning.net > /dev/null 2>&1; then ((success_count++)); else ((warning_count++)); fi

echo "Tests completed:"
echo "  ✅ Successes: $success_count"
echo "  ⚠️  Warnings: $warning_count"
echo "  ❌ Errors: $error_count"
echo

if [[ $error_count -eq 0 ]]; then
    if [[ $warning_count -eq 0 ]]; then
        print_success "All tests passed! Your Azure IoT service is properly configured."
    else
        print_warning "Setup is mostly complete with $warning_count warnings. Review the warnings above."
    fi
else
    print_error "Setup has $error_count errors that need to be resolved."
    exit 1
fi

echo
echo "Next steps:"
echo "1. Check service status: sudo systemctl status azure-iot.service"
echo "2. View real-time logs: sudo journalctl -u azure-iot.service -f"
echo "3. Monitor the service for a few minutes to ensure stable operation"
echo "4. Check your Azure IoT Hub to see if the device is connected"
