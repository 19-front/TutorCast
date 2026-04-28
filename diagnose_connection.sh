#!/bin/bash

# TutorCast Connection Diagnostic Tool
# Helps troubleshoot plugin and network connectivity

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
}

print_check() {
    echo -e "${YELLOW}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Get VM IP from TutorCast defaults
get_vm_ip() {
    VM_IP=$(defaults read com.tutorcast.app AutoCADParallelsIP 2>/dev/null || echo "")
    if [ -z "$VM_IP" ]; then
        VM_IP=$(defaults read /Users/nana/Library/Preferences/com.tutorcast.app AutoCADParallelsIP 2>/dev/null || echo "")
    fi
    echo "$VM_IP"
}

print_header "TutorCast Plugin Connection Diagnostic"

# Test 1: TutorCast App Status
print_check "Test 1: TutorCast App Status"
if pgrep -f "TutorCast" > /dev/null; then
    print_success "TutorCast app is running"
    pid=$(pgrep -f "TutorCast" | head -1)
    print_info "Process ID: $pid"
else
    print_error "TutorCast app is not running"
    print_info "Launch TutorCast from Applications folder"
fi
echo ""

# Test 2: Get VM IP
print_check "Test 2: VM Configuration"
VM_IP=$(get_vm_ip)
PORT=$(defaults read com.tutorcast.app AutoCADParallelsPort 2>/dev/null || echo "19848")

if [ -z "$VM_IP" ]; then
    print_error "VM IP not configured"
    read -p "Enter VM IP (e.g., 192.168.1.105): " VM_IP
    if [ -z "$VM_IP" ]; then
        print_error "VM IP required for testing"
        exit 1
    fi
    defaults write com.tutorcast.app AutoCADParallelsIP "$VM_IP"
    print_success "VM IP set to: $VM_IP"
else
    print_success "VM IP configured: $VM_IP"
fi
print_info "Port: $PORT"
echo ""

# Test 3: Network Connectivity
print_check "Test 3: Network Connectivity"
if ping -c 1 -W 2 "$VM_IP" &> /dev/null; then
    print_success "VM is reachable at $VM_IP"
else
    print_error "Cannot ping VM at $VM_IP"
    print_info "Possible issues:"
    print_info "  - VM is not running"
    print_info "  - VM IP is incorrect"
    print_info "  - Network connection issue"
    print_info "  - VM firewall blocking ICMP"
fi
echo ""

# Test 4: Port Connectivity
print_check "Test 4: Port $PORT Connectivity"
print_info "Attempting to connect to $VM_IP:$PORT..."

if timeout 2 bash -c "echo > /dev/tcp/$VM_IP/$PORT" 2>/dev/null; then
    print_success "Port $PORT is OPEN and listening"
    print_info "Plugin is likely running on VM"
else
    print_error "Port $PORT is CLOSED or not responding"
    echo ""
    print_info "Troubleshooting steps:"
    echo "  1. Verify plugin is loaded in AutoCAD:"
    echo "     - AutoCAD: Tools → Load Application"
    echo "     - Check for TutorCastPlugin.exe"
    echo ""
    echo "  2. Check Windows firewall on VM:"
    echo "     - netstat -an | findstr $PORT (should show LISTENING)"
    echo ""
    echo "  3. Allow port through firewall:"
    echo "     netsh advfirewall firewall add rule name=\"TutorCast\" dir=in action=allow protocol=tcp localport=$PORT"
    echo ""
    echo "  4. Verify IP address:"
    echo "     - On Windows VM: ipconfig"
    echo "     - Compare with configured IP: $VM_IP"
fi
echo ""

# Test 5: TutorCast Listener Status
print_check "Test 5: TutorCast Listener Status"
if pgrep -f "TutorCast" > /dev/null; then
    print_success "TutorCast is running (listener should be active)"
    print_info "Checking system logs..."
    
    # Check recent logs
    recent_events=$(log show --predicate 'process == "TutorCast"' --last 5m 2>/dev/null | grep -i "listener\|connect\|receive" | tail -5)
    
    if [ -n "$recent_events" ]; then
        print_success "Recent TutorCast listener activity detected"
        echo "$recent_events" | sed 's/^/    /'
    else
        print_info "No recent listener activity (might be normal if idle)"
    fi
else
    print_error "TutorCast not running - start it first"
fi
echo ""

# Test 6: Manual Connection Test
print_check "Test 6: Send Test Event"
read -p "Send test event to plugin? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    test_event='{"type":"test","commandName":"TEST_COMMAND","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
    print_info "Sending test event: $test_event"
    
    if echo "$test_event" | nc -w 1 "$VM_IP" "$PORT" 2>/dev/null; then
        print_success "Event sent successfully"
    else
        print_error "Failed to send event (port may not be accepting connections)"
    fi
fi
echo ""

# Test 7: Plugin File Verification
print_check "Test 7: Plugin File Verification"
print_info "Expected plugin locations:"

plugin_locations=(
    "~/Plugins/Windows/TutorCastPlugin.exe"
    "~/Desktop/TutorCastPlugin.exe"
    "./Plugins/Windows/TutorCastPlugin.exe"
    "/Volumes/Parallels/Windows/Users/user/AppData/Local/TutorCast/TutorCastPlugin.exe"
)

found=false
for loc in "${plugin_locations[@]}"; do
    expanded_loc=$(eval echo "$loc")
    if [ -f "$expanded_loc" ]; then
        print_success "Plugin found: $loc"
        found=true
    fi
done

if [ "$found" = false ]; then
    print_error "Plugin file not found in common locations"
    print_info "Build plugin with: C# compiler or Visual Studio"
    print_info "Location on Windows VM should be:"
    print_info "  C:\\Users\\user\\AppData\\Local\\TutorCast\\TutorCastPlugin.exe"
fi
echo ""

# Test 8: Network Interface Check
print_check "Test 8: Local Network Interface"
local_ip=$(ifconfig | grep -A1 "inet " | grep -v "127.0.0.1" | head -1 | awk '{print $2}')
print_info "Your macOS IP: $local_ip"

# Check if on same subnet
if [[ $VM_IP =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+$ ]] && [[ $local_ip =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+$ ]]; then
    vm_subnet="${BASH_REMATCH[1]}"
    local_subnet="${BASH_REMATCH[1]}"
    
    if [ "$vm_subnet" = "$local_subnet" ]; then
        print_success "VM and macOS on same subnet: $vm_subnet.0/24"
    else
        print_error "VM and macOS on different subnets"
        print_info "VM subnet: $vm_subnet.0/24"
        print_info "macOS subnet: $local_subnet.0/24"
    fi
fi
echo ""

# Test 9: AutoCAD Detection
print_check "Test 9: AutoCAD Environment Detection"
print_info "TutorCast auto-detection scans:"
print_info "  - Native macOS AutoCAD (via AXUIElement)"
print_info "  - Parallels Windows VM (via TCP port scan)"

if pgrep -f "TutorCast" > /dev/null; then
    detected=$(defaults read com.tutorcast.app DetectedAutoCADEnvironment 2>/dev/null || echo "not set")
    print_info "Detected environment: $detected"
    
    if [[ "$detected" == *"Parallels"* ]] || [[ "$detected" == *"parallels"* ]]; then
        print_success "Parallels environment detected"
    else
        print_error "Parallels environment not detected yet"
        print_info "Run AutoCAD command to trigger detection"
    fi
fi
echo ""

# Test 10: Summary & Recommendations
print_header "Summary & Next Steps"

echo ""
print_info "QUICK CHECKLIST:"
echo "  [ ] VM is running and IP is: $VM_IP"
echo "  [ ] Can ping VM from macOS"
echo "  [ ] Port $PORT is open/listening on VM"
echo "  [ ] Plugin is loaded in AutoCAD on VM"
echo "  [ ] TutorCast app is running on macOS"
echo ""

print_info "TO FULLY TEST:"
echo "  1. In AutoCAD (Windows VM): Type 'LINE' command"
echo "  2. Watch TutorCast overlay on macOS"
echo "  3. Should show 'LIN' (abbreviated)"
echo "  4. As you use the command, overlay updates"
echo ""

print_info "IF TESTS FAIL:"
echo "  1. Check Windows Firewall on VM"
echo "  2. Verify plugin loaded in AutoCAD"
echo "  3. Review logs: log stream --predicate 'process == \"TutorCast\"' --level debug"
echo "  4. Check plugin console output on Windows VM"
echo ""

# Save diagnostic info
log_file="$HOME/Desktop/tutorcast_diagnostic_$(date +%Y%m%d_%H%M%S).txt"
{
    echo "TutorCast Diagnostic Report"
    echo "Generated: $(date)"
    echo ""
    echo "Configuration:"
    echo "  VM IP: $VM_IP"
    echo "  Port: $PORT"
    echo "  macOS IP: $local_ip"
    echo ""
    echo "App Status:"
    pgrep -f "TutorCast" > /dev/null && echo "  TutorCast: Running" || echo "  TutorCast: Not running"
    echo ""
    echo "Network Test:"
    ping -c 1 "$VM_IP" 2>&1 || true
    echo ""
} > "$log_file"

print_success "Diagnostic report saved to: $log_file"
echo ""
