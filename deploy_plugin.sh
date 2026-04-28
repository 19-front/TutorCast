#!/bin/bash

# TutorCast Plugin Deployment Helper
# Automates plugin setup for Parallels VM connection

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PARALLELS_VM_NAME="${1:-Windows}"
TUTORCAST_PLUGIN_DIR="Plugins/Windows"
PLUGIN_FILENAME="TutorCastPlugin.exe"
VM_TARGET_DIR="C:\\Users\\\\user\\\\AppData\\\\Local\\\\TutorCast\\\\"
PORT=19848

echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   TutorCast Plugin Deployment Helper       ║${NC}"
echo -e "${BLUE}║   For AutoCAD in Parallels Desktop         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

# Function to print section headers
print_section() {
    echo -e "${YELLOW}▶ $1${NC}"
}

# Function to print success
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print error
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Step 1: Check Prerequisites
print_section "Step 1: Checking Prerequisites"

if ! command -v prlctl &> /dev/null; then
    print_error "Parallels Desktop not installed or not in PATH"
    echo "Install Parallels Desktop or ensure prlctl is available"
    exit 1
fi
print_success "Parallels Desktop found"

if [ ! -f "$TUTORCAST_PLUGIN_DIR/$PLUGIN_FILENAME" ]; then
    print_error "Plugin not found at $TUTORCAST_PLUGIN_DIR/$PLUGIN_FILENAME"
    echo "Build the plugin first or check the path"
    exit 1
fi
print_success "Plugin file found"

# Step 2: Detect VM IP
print_section "Step 2: Detecting Parallels VM Network"

echo "Available VMs:"
prlctl list --all | tail -n +2

read -p "Enter VM name (default: '$PARALLELS_VM_NAME'): " vm_input
PARALLELS_VM_NAME="${vm_input:-$PARALLELS_VM_NAME}"

# Get VM IP
VM_IP=$(prlctl exec "$PARALLELS_VM_NAME" ipconfig 2>/dev/null | grep "IPv4 Address" | head -1 | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' || true)

if [ -z "$VM_IP" ]; then
    print_error "Could not detect VM IP automatically"
    read -p "Enter VM IP manually (e.g., 192.168.1.105): " VM_IP
fi

if [ -z "$VM_IP" ]; then
    print_error "VM IP not specified"
    exit 1
fi

print_success "VM IP: $VM_IP"

# Step 3: Test VM Connectivity
print_section "Step 3: Testing VM Connectivity"

if ping -c 1 -W 1 "$VM_IP" &> /dev/null; then
    print_success "VM is reachable at $VM_IP"
else
    print_error "VM not reachable at $VM_IP"
    echo "Troubleshooting:"
    echo "  - Verify VM is running"
    echo "  - Check network configuration"
    echo "  - Ensure VM and macOS are on same subnet"
fi

# Step 4: Copy Plugin to VM
print_section "Step 4: Deploying Plugin to VM"

echo "This will copy the plugin to the Windows VM"
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 0
fi

# Create directory on VM if needed
print_success "Creating plugin directory on VM..."
prlctl exec "$PARALLELS_VM_NAME" "cmd /c mkdir \"C:\\Users\\user\\AppData\\Local\\TutorCast\" 2>nul || exit /b 0" || true

# Copy plugin
print_success "Copying plugin file..."
scp -o StrictHostKeyChecking=no "$TUTORCAST_PLUGIN_DIR/$PLUGIN_FILENAME" "user@$VM_IP:C:\\Users\\user\\AppData\\Local\\TutorCast\\" || {
    print_error "Failed to copy plugin via SCP"
    echo "Alternative: Manually copy from macOS:"
    echo "  scp $TUTORCAST_PLUGIN_DIR/$PLUGIN_FILENAME user@$VM_IP:C:\\\\Users\\\\user\\\\AppData\\\\Local\\\\TutorCast\\\\"
    exit 1
}
print_success "Plugin deployed to VM"

# Step 5: Verify Plugin
print_section "Step 5: Verifying Plugin Installation"

echo "Plugin file should be at:"
echo "  C:\\Users\\user\\AppData\\Local\\TutorCast\\$PLUGIN_FILENAME"

ssh -o StrictHostKeyChecking=no "user@$VM_IP" "dir \"C:\\Users\\user\\AppData\\Local\\TutorCast\\\"" || true

# Step 6: Configure AutoCAD
print_section "Step 6: Configuring AutoCAD to Load Plugin"

echo ""
echo "Next steps in AutoCAD (on Windows VM):"
echo "  1. Launch AutoCAD"
echo "  2. Go to: Tools → Load Application (or APPLOAD)"
echo "  3. Browse to: C:\\Users\\user\\AppData\\Local\\TutorCast\\$PLUGIN_FILENAME"
echo "  4. Click 'Load' then 'Close'"
echo "  5. Optional: Check 'Startup Suite' to auto-load next time"
echo ""
echo "Or via AutoLISP:"
echo "  (command \"APPLOAD\" \"C:\\\\Users\\\\user\\\\AppData\\\\Local\\\\TutorCast\\\\$PLUGIN_FILENAME\")"
echo ""

read -p "Have you loaded the plugin in AutoCAD? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_success "Plugin loaded in AutoCAD"
else
    echo "Please load the plugin before continuing"
fi

# Step 7: Test Connection
print_section "Step 7: Testing Connection"

echo "Testing port $PORT on $VM_IP..."
if nc -zv -w 1 "$VM_IP" $PORT 2>&1 | grep -q succeeded; then
    print_success "Port $PORT is open and listening"
else
    print_error "Could not connect to port $PORT"
    echo "Troubleshooting:"
    echo "  - Verify plugin is loaded in AutoCAD"
    echo "  - Check Windows Firewall settings"
    echo "  - Ensure plugin is running: netstat -an | findstr $PORT (on Windows)"
fi

# Step 8: Configure TutorCast
print_section "Step 8: Configuring TutorCast App"

echo "Setting TutorCast preferences..."
defaults write com.tutorcast.app AutoCADParallelsIP "$VM_IP"
defaults write com.tutorcast.app AutoCADParallelsPort $PORT
print_success "TutorCast configured for: $VM_IP:$PORT"

# Step 9: Summary
print_section "Setup Summary"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Deployment Summary                 ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo "VM Details:"
echo "  Name: $PARALLELS_VM_NAME"
echo "  IP: $VM_IP"
echo "  Port: $PORT"
echo ""
echo "Plugin Location (on VM):"
echo "  C:\\Users\\user\\AppData\\Local\\TutorCast\\$PLUGIN_FILENAME"
echo ""
echo "Next Steps:"
echo "  1. Launch TutorCast on macOS"
echo "  2. In AutoCAD (Windows VM), run a command (e.g., LINE, OFFSET)"
echo "  3. Watch TutorCast overlay for command updates"
echo ""
echo "Troubleshooting:"
echo "  - Check: log stream --predicate 'process == \"TutorCast\"' (macOS logs)"
echo "  - Check: netstat -an | findstr $PORT (Windows - verify listening)"
echo "  - Manual test: nc -zv $VM_IP $PORT (test connectivity)"
echo ""

print_success "Setup Complete!"
echo ""
echo "For detailed help, see: PLUGIN_CONNECTION_GUIDE.md"
