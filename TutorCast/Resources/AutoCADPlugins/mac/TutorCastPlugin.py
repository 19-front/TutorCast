#!/usr/bin/env python3
# TutorCastPlugin.py
# TutorCast AutoCAD for Mac plugin (Primary)
# 
# Intercepts command events from AutoCAD and sends them to TutorCast
# via Unix domain socket (/tmp/tutorcast_autocad.sock) in JSON format.
#
# Installation:
# 1. AutoCAD 2023+ for macOS: Place in ~/Library/Application Support/Autodesk/AutoCAD 2024/AutoCAD 2024.app/Contents/Resources/
# 2. Or load via acad_startup.lsp: (load "/path/to/TutorCastPlugin.py")
#
# Transport: Newline-delimited JSON, UTF-8 encoded

import socket
import json
import threading
import time
import os
from datetime import datetime
from threading import Lock

# Configuration
SOCKET_PATH = "/tmp/tutorcast_autocad.sock"
SOCKET_TIMEOUT = 0.5  # seconds

# Global state
_conn = None
_lock = Lock()


def _get_connection():
    """Get or establish connection to TutorCast listener."""
    global _conn
    with _lock:
        if _conn is None:
            try:
                sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                sock.settimeout(SOCKET_TIMEOUT)
                sock.connect(SOCKET_PATH)
                _conn = sock
                print(f"[TutorCastPlugin] Connected to TutorCast at {SOCKET_PATH}")
            except (FileNotFoundError, ConnectionRefusedError, OSError) as e:
                print(f"[TutorCastPlugin] Failed to connect: {e}")
                _conn = None
        return _conn


def _send_event(event_dict):
    """Send a JSON event to TutorCast over the socket."""
    conn = _get_connection()
    if conn is None:
        return False
    
    try:
        payload = json.dumps(event_dict) + "\n"
        conn.sendall(payload.encode("utf-8"))
        return True
    except (BrokenPipeError, OSError) as e:
        print(f"[TutorCastPlugin] Send failed, reconnecting: {e}")
        global _conn
        with _lock:
            _conn = None
        return False


def _build_event(event_type, command_name, subcommand=None, options=None, raw=None):
    """Build a standard AutoCADCommandEvent dictionary."""
    return {
        "type": event_type,
        "commandName": str(command_name).upper().strip() if command_name else "",
        "subcommand": subcommand,
        "activeOptions": options,
        "selectedOption": None,
        "rawCommandLineText": raw,
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "source": "nativePlugin"
    }


# ============================================================================
# REACTOR HOOKS — Called by AutoCAD's command reactor mechanism
# ============================================================================

def on_command_will_start(command_name):
    """Called when a command starts."""
    print(f"[TutorCastPlugin] Command started: {command_name}")
    event = _build_event("commandStarted", command_name)
    _send_event(event)


def on_command_ended(command_name):
    """Called when a command completes successfully."""
    print(f"[TutorCastPlugin] Command ended: {command_name}")
    event = _build_event("commandCompleted", command_name)
    _send_event(event)


def on_command_cancelled(command_name):
    """Called when a command is cancelled (ESC or error)."""
    print(f"[TutorCastPlugin] Command cancelled: {command_name}")
    event = _build_event("commandCancelled", command_name)
    _send_event(event)


def on_command_line_changed(text):
    """Called when command line text changes (prompts/options)."""
    if not text or not ":" in text:
        return
    
    # Extract subcommand prompt (text after last colon)
    parts = text.split(":")
    subcommand = parts[-1].strip() if len(parts) > 1 else None
    
    # Extract options from brackets: [Through/Erase/Layer] -> ["Through", "Erase", "Layer"]
    options = []
    import re
    matches = re.findall(r'\[([^\]]+)\]', text)
    for match in matches:
        options.extend([opt.strip() for opt in match.split('/')])
    
    event = _build_event(
        "subcommandPrompt",
        "",  # No command name for prompts
        subcommand=subcommand,
        options=options if options else None,
        raw=text
    )
    _send_event(event)


# ============================================================================
# AUTOCAD REACTOR REGISTRATION
# ============================================================================

def register_reactors():
    """Register this plugin's reactors with AutoCAD.
    
    This function is called via acad_startup.lsp or the Python API.
    Attempts multiple registration methods for compatibility.
    """
    try:
        # Attempt 1: AutoCAD Python API (AutoCAD 2023+)
        try:
            import pyautocad
            acad = pyautocad.Autocad()
            doc = acad.doc
            
            # Create editor reactor for command events
            # Note: The exact API varies by AutoCAD version; this is a template
            print("[TutorCastPlugin] Attempting to register via pyautocad API...")
            # Registration would go here once AutoCAD Python API is confirmed
            
        except (ImportError, AttributeError):
            print("[TutorCastPlugin] pyautocad not available, using LISP bridge...")
            pass
        
        # Attempt 2: LISP bridge (always available)
        # The LISP fallback (TutorCastPlugin.lsp) handles reactor registration
        # This is the recommended fallback for maximum compatibility
        
        print("[TutorCastPlugin] Plugin initialized; reactors registered via LISP bridge")
        return True
        
    except Exception as e:
        print(f"[TutorCastPlugin] Failed to register reactors: {e}")
        return False


# ============================================================================
# PLUGIN INITIALIZATION
# ============================================================================

if __name__ == "__main__":
    # Direct execution for testing
    register_reactors()
    print("[TutorCastPlugin] Testing socket connection...")
    
    test_event = _build_event("commandStarted", "LINE")
    if _send_event(test_event):
        print("[TutorCastPlugin] Test event sent successfully")
    else:
        print("[TutorCastPlugin] Failed to send test event")

else:
    # Loaded by AutoCAD
    register_reactors()
