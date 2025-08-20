#!/bin/bash

# Uninstall script for Azure IoT service
# This script removes the service and cleans up all installed files

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
echo "Azure IoT Service Uninstaller"
echo "=========================================="
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

# Confirmation prompt
echo "This script will remove the Azure IoT service and all related files."
echo "This action cannot be undone."
echo
read -p "Are you sure you want to continue? (y/N): " -r response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    print_status "Uninstall cancelled"
    exit 0
fi

echo

# Step 1: Stop and disable the service
print_status "Stopping and disabling Azure IoT service..."
if systemctl is-active azure-iot.service > /dev/null 2>&1; then
    systemctl stop azure-iot.service
    print_success "Service stopped"
else
    print_status "Service was not running"
fi

if systemctl is-enabled azure-iot.service > /dev/null 2>&1; then
    systemctl disable azure-iot.service
    print_success "Service disabled"
else
    print_status "Service was not enabled"
fi

# Step 2: Remove systemd service file
print_status "Removing systemd service file..."
if [[ -f /etc/systemd/system/azure-iot.service ]]; then
    rm /etc/systemd/system/azure-iot.service
    print_success "Service file removed"
else
    print_status "Service file not found"
fi

# Step 3: Reload systemd
print_status "Reloading systemd..."
systemctl daemon-reload
print_success "Systemd reloaded"

# Step 4: Remove service files
print_status "Removing service files..."
if [[ -d /opt/azure-iot ]]; then
    rm -rf /opt/azure-iot
    print_success "Service directory removed"
else
    print_status "Service directory not found"
fi

# Step 5: Remove configuration files
print_status "Removing configuration files..."
if [[ -d /etc/azureiotpnp ]]; then
    rm -rf /etc/azureiotpnp
    print_success "Configuration directory removed"
else
    print_status "Configuration directory not found"
fi

# Step 6: Remove log files
print_status "Removing log files..."
if [[ -f /var/log/azure-iot-service.log ]]; then
    rm /var/log/azure-iot-service.log
    print_success "Log file removed"
else
    print_status "Log file not found"
fi

# Step 7: Optionally remove Python dependencies
echo
read -p "Do you want to remove Azure IoT Python dependencies? (y/N): " -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    print_status "Removing Azure IoT Python dependencies..."
    if pip3 show azure-iot-device > /dev/null 2>&1; then
        pip3 uninstall -y azure-iot-device
        print_success "Azure IoT Device SDK removed"
    else
        print_status "Azure IoT Device SDK not found"
    fi
else
    print_status "Keeping Python dependencies"
fi

echo
echo "=========================================="
echo "Uninstall Complete!"
echo "=========================================="
echo
print_success "Azure IoT service has been completely removed from your system."
echo
echo "Removed components:"
echo "  ✅ Systemd service file"
echo "  ✅ Service executable files"
echo "  ✅ Configuration files"
echo "  ✅ Log files"
if [[ "$response" =~ ^[Yy]$ ]]; then
    echo "  ✅ Python dependencies"
fi
echo
echo "Note: If you want to reinstall the service later, you can run the setup script again."
echo "      Your previous configuration will need to be re-entered."
