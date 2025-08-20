#!/bin/bash

# Azure IoT Environment Setup Script for Raspberry Pi
# This script automates the complete setup of Azure IoT services

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to check if running on Raspberry Pi
check_raspberry_pi() {
    if ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
        print_warning "This script is designed for Raspberry Pi. Continue anyway? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_error "Setup cancelled"
            exit 1
        fi
    fi
}

# Function to get user input for configuration
get_config_input() {
    print_status "Please provide the following Azure IoT configuration details:"
    echo
    
    read -p "Enter your ID Scope: " ID_SCOPE
    read -p "Enter your Registration ID: " REGISTRATION_ID
    read -p "Enter your Primary Key: " PRIMARY_KEY
    read -p "Enter your Site Name: " SITE_NAME
    read -p "Enter your Truck Number: " TRUCK_NUMBER
    
    # Validate inputs
    if [[ -z "$ID_SCOPE" || -z "$REGISTRATION_ID" || -z "$PRIMARY_KEY" || -z "$SITE_NAME" || -z "$TRUCK_NUMBER" ]]; then
        print_error "All fields are required. Please run the script again."
        exit 1
    fi
    
    print_success "Configuration details captured"
}

# Function to update system packages
update_system() {
    print_status "Updating system packages..."
    apt update -y
    print_success "System packages updated"
}

# Function to install Python and dependencies
install_dependencies() {
    print_status "Installing Python and Azure IoT dependencies..."
    
    # Install Python3 and pip if not present
    if ! command -v python3 &> /dev/null; then
        apt install -y python3
    fi
    
    if ! command -v pip3 &> /dev/null; then
        apt install -y python3-pip
    fi
    
    # Install Azure IoT Device SDK
    pip3 install --break-system-packages azure-iot-device
    
    print_success "Dependencies installed"
}

# Function to create configuration files
create_config_files() {
    print_status "Creating configuration files..."
    
    # Create configuration directory
    mkdir -p /etc/azureiotpnp
    
    # Create provisioning config
    cat > /etc/azureiotpnp/provisioning_config.json << EOF
{
  "globalEndpoint": "global.azure-devices-provisioning.net",
  "idScope": "$ID_SCOPE",
  "registrationId": "$REGISTRATION_ID",
  "symmetricKey": "$PRIMARY_KEY",
  "tag": {
    "nexusLocate": {
      "siteName": "$SITE_NAME",
      "truckNumber": "$TRUCK_NUMBER"
    }
  }
}
EOF
    
    # Set proper permissions
    chmod 600 /etc/azureiotpnp/provisioning_config.json
    
    print_success "Configuration files created"
}

# Function to create service directory and copy files
setup_service_files() {
    print_status "Setting up service files..."
    
    # Create service directory
    mkdir -p /opt/azure-iot
    
    # Copy the IoT service script
    cp iot_service.py /opt/azure-iot/
    
    # Copy the systemd service file
    cp azure-iot.service /etc/systemd/system/
    
    # Make script executable
    chmod +x /opt/azure-iot/iot_service.py
    
    print_success "Service files set up"
}

# Function to create log directory
setup_logging() {
    print_status "Setting up logging..."
    
    # Create log directory and file
    mkdir -p /var/log
    touch /var/log/azure-iot-service.log
    chmod 644 /var/log/azure-iot-service.log
    
    print_success "Logging set up"
}

# Function to enable and start the service
enable_service() {
    print_status "Enabling and starting Azure IoT service..."
    
    # Reload systemd to recognize new service
    systemctl daemon-reload
    
    # Enable service to start on boot
    systemctl enable azure-iot.service
    
    # Start the service
    systemctl start azure-iot.service
    
    print_success "Service enabled and started"
}

# Function to verify installation
verify_installation() {
    print_status "Verifying installation..."
    
    # Check if service is running
    if systemctl is-active --quiet azure-iot.service; then
        print_success "Azure IoT service is running"
    else
        print_error "Azure IoT service is not running"
        print_status "Checking service status..."
        systemctl status azure-iot.service
        exit 1
    fi
    
    # Check if configuration file exists
    if [[ -f /etc/azureiotpnp/provisioning_config.json ]]; then
        print_success "Configuration file exists"
    else
        print_error "Configuration file not found"
        exit 1
    fi
    
    # Check if service file exists
    if [[ -f /etc/systemd/system/azure-iot.service ]]; then
        print_success "Systemd service file exists"
    else
        print_error "Systemd service file not found"
        exit 1
    fi
    
    print_success "Installation verified successfully!"
}

# Function to display final instructions
show_final_instructions() {
    echo
    echo "=========================================="
    echo "Azure IoT Environment Setup Complete!"
    echo "=========================================="
    echo
    echo "Service Status:"
    echo "  Check status: sudo systemctl status azure-iot.service"
    echo "  View logs: sudo journalctl -u azure-iot.service -f"
    echo "  Restart service: sudo systemctl restart azure-iot.service"
    echo "  Stop service: sudo systemctl stop azure-iot.service"
    echo
    echo "Configuration:"
    echo "  Config file: /etc/azureiotpnp/provisioning_config.json"
    echo "  Service file: /etc/systemd/system/azure-iot.service"
    echo "  Log file: /var/log/azure-iot-service.log"
    echo
    echo "The service will automatically start on boot."
    echo
}

# Main execution
main() {
    echo "=========================================="
    echo "Azure IoT Environment Setup Script"
    echo "=========================================="
    echo
    
    # Check prerequisites
    check_root
    check_raspberry_pi
    
    # Get configuration input
    get_config_input
    
    # Execute setup steps
    update_system
    install_dependencies
    create_config_files
    setup_service_files
    setup_logging
    enable_service
    verify_installation
    
    # Show final instructions
    show_final_instructions
}

# Run main function
main "$@"
