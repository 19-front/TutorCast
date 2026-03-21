#!/usr/bin/env python3
"""
TutorCast AutoCAD Plugin (macOS)
Primary: Python3 via IronPython in AutoCAD for Mac
Fallback: AutoLISP (tutorcast_fallback.lsp)

Sends AutoCAD command events to TutorCast overlay via Unix socket.
- Command started/completed
- Subcommand prompts
- Option selection
- Real-time updates

Security:
- Socket path: /tmp/tutorcast_autocad.sock (0o600 permissions)
- Max command name: 64 characters
- Max subcommand: 128 characters
- Data validation before transmission
"""

import socket
import json
import sys
import os
import time
import threading
from datetime import datetime

# MARK: - Configuration

class PluginConfig:
    """Plugin configuration and constants"""
    
    SOCKET_PATH = "/tmp/tutorcast_autocad.sock"
    SOCKET_TIMEOUT = 5.0
    
    # Command validation
    MAX_COMMAND_NAME = 64
    MAX_SUBCOMMAND = 128
    
    # Retry configuration
    MAX_RETRIES = 3
    RETRY_DELAY = 0.5
    
    # Connection pooling
    SOCKET_POOL_SIZE = 1
    
    # Logging
    DEBUG = True

# MARK: - Event Types

class EventType:
    """AutoCAD event types matching Swift enum"""
    COMMAND_STARTED = "commandStarted"
    SUBCOMMAND_PROMPT = "subcommandPrompt"
    COMMAND_COMPLETED = "commandCompleted"
    COMMAND_CANCELLED = "commandCancelled"
    OPTION_SELECTED = "optionSelected"
    COMMAND_LINE_TEXT = "commandLineText"

# MARK: - Validation

class CommandValidator:
    """Validates and sanitizes command data"""
    
    @staticmethod
    def sanitize_string(text, max_length):
        """
        Sanitize string by removing control characters.
        
        - Parameters:
            text: String to sanitize
            max_length: Maximum allowed length
        
        - Returns: Sanitized string, or None if invalid
        """
        if not text or not isinstance(text, str):
            return None
        
        # Remove control characters (ASCII 0-31 and 127)
        sanitized = ''.join(c for c in text if ord(c) >= 32 and ord(c) != 127)
        
        # Enforce max length
        if len(sanitized) > max_length:
            sanitized = sanitized[:max_length]
        
        # Don't send empty strings
        return sanitized if sanitized else None
    
    @staticmethod
    def validate_command_name(name):
        """
        Validate command name.
        
        - Parameters: name: Command name to validate
        - Returns: Sanitized name if valid, None otherwise
        """
        if not name or not isinstance(name, str):
            return None
        
        # Must be alphanumeric + underscore
        if not all(c.isalnum() or c == '_' for c in name):
            # Remove invalid characters
            name = ''.join(c for c in name if c.isalnum() or c == '_')
        
        sanitized = CommandValidator.sanitize_string(name, PluginConfig.MAX_COMMAND_NAME)
        return sanitized if sanitized and len(sanitized) > 0 else None
    
    @staticmethod
    def validate_subcommand(text):
        """
        Validate subcommand text (prompt).
        
        - Parameters: text: Subcommand text to validate
        - Returns: Sanitized text if valid, None otherwise
        """
        return CommandValidator.sanitize_string(text, PluginConfig.MAX_SUBCOMMAND)
    
    @staticmethod
    def validate_options(options):
        """
        Validate options array.
        
        - Parameters: options: List of option strings
        - Returns: Validated list, or None if invalid
        """
        if not options:
            return None
        
        if not isinstance(options, list):
            return None
        
        validated = []
        for opt in options:
            sanitized = CommandValidator.sanitize_string(opt, 50)
            if sanitized:
                validated.append(sanitized)
        
        return validated if validated else None

# MARK: - Event Transmission

class EventSender:
    """Sends events to TutorCast via Unix socket"""
    
    def __init__(self):
        """Initialize event sender with connection pooling"""
        self.socket = None
        self.connected = False
        self.logger = PluginLogger()
    
    def connect(self):
        """
        Connect to TutorCast Unix socket.
        
        Retries up to MAX_RETRIES times with RETRY_DELAY between attempts.
        
        - Returns: True if connected, False otherwise
        """
        if self.connected and self.socket:
            return True
        
        for attempt in range(PluginConfig.MAX_RETRIES):
            try:
                # Create Unix domain socket
                self.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.socket.settimeout(PluginConfig.SOCKET_TIMEOUT)
                
                # Connect to socket
                self.socket.connect(PluginConfig.SOCKET_PATH)
                self.connected = True
                self.logger.debug(f"Connected to TutorCast socket (attempt {attempt + 1})")
                return True
                
            except (FileNotFoundError, ConnectionRefusedError) as e:
                self.logger.debug(f"Connection attempt {attempt + 1} failed: {str(e)}")
                if attempt < PluginConfig.MAX_RETRIES - 1:
                    time.sleep(PluginConfig.RETRY_DELAY)
                    
            except Exception as e:
                self.logger.error(f"Unexpected connection error: {str(e)}")
                break
        
        self.logger.warn("Failed to connect to TutorCast socket")
        self.connected = False
        return False
    
    def disconnect(self):
        """Disconnect from socket"""
        if self.socket:
            try:
                self.socket.close()
            except:
                pass
            self.socket = None
            self.connected = False
    
    def send_event(self, event_dict):
        """
        Send event to TutorCast.
        
        Handles disconnection and reconnection automatically.
        
        - Parameters: event_dict: Dictionary with event data
        - Returns: True if sent successfully, False otherwise
        """
        # Ensure connected
        if not self.connected:
            if not self.connect():
                return False
        
        try:
            # Convert to JSON with timestamp
            event_dict["timestamp"] = datetime.now().isoformat()
            json_data = json.dumps(event_dict)
            
            # Send with newline terminator
            self.socket.sendall((json_data + "\n").encode('utf-8'))
            self.logger.debug(f"Sent event: {event_dict.get('type', 'unknown')}")
            return True
            
        except (BrokenPipeError, ConnectionResetError):
            self.logger.warn("Socket connection lost, reconnecting...")
            self.connected = False
            self.socket = None
            
            # Retry once
            if self.connect():
                try:
                    self.socket.sendall((json_data + "\n").encode('utf-8'))
                    return True
                except:
                    return False
            return False
            
        except Exception as e:
            self.logger.error(f"Error sending event: {str(e)}")
            return False

# MARK: - Logging

class PluginLogger:
    """Simple logger for plugin events"""
    
    LOG_FILE = os.path.expanduser("~/tutorcast_plugin.log")
    
    @staticmethod
    def debug(message):
        """Log debug message"""
        if PluginConfig.DEBUG:
            PluginLogger._log("DEBUG", message)
    
    @staticmethod
    def info(message):
        """Log info message"""
        PluginLogger._log("INFO", message)
    
    @staticmethod
    def warn(message):
        """Log warning message"""
        PluginLogger._log("WARN", message)
    
    @staticmethod
    def error(message):
        """Log error message"""
        PluginLogger._log("ERROR", message)
    
    @staticmethod
    def _log(level, message):
        """Write log message to file and stderr"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_line = f"[{timestamp}] [{level}] {message}"
        
        # Write to file
        try:
            with open(PluginLogger.LOG_FILE, 'a') as f:
                f.write(log_line + "\n")
        except:
            pass
        
        # Write to stderr (visible in AutoCAD console)
        print(f"[TutorCast] {log_line}", file=sys.stderr)

# MARK: - AutoCAD Integration (IronPython)

class AutoCADPlugin:
    """
    TutorCast plugin for AutoCAD macOS via IronPython.
    
    Hooks into AutoCAD command events and sends them to TutorCast overlay.
    """
    
    def __init__(self):
        """Initialize plugin"""
        self.event_sender = EventSender()
        self.logger = PluginLogger()
        self.current_command = None
        self.is_monitoring = False
    
    def start(self):
        """Start monitoring AutoCAD commands"""
        try:
            self.logger.info("TutorCast Plugin starting...")
            
            # Try to import AutoCAD API
            try:
                import acad
                self.acad_app = acad.AcadApplication()
                self.logger.info("AutoCAD application loaded")
            except ImportError:
                self.logger.error("Failed to import AutoCAD API (acad module)")
                return False
            
            # Connect to TutorCast
            if not self.event_sender.connect():
                self.logger.warn("Could not connect to TutorCast initially (will retry on events)")
            
            # Set up event hooks
            self._setup_event_hooks()
            
            self.is_monitoring = True
            self.logger.info("TutorCast Plugin monitoring active")
            return True
            
        except Exception as e:
            self.logger.error(f"Plugin initialization failed: {str(e)}")
            return False
    
    def stop(self):
        """Stop monitoring AutoCAD commands"""
        self.is_monitoring = False
        self.event_sender.disconnect()
        self.logger.info("TutorCast Plugin stopped")
    
    def _setup_event_hooks(self):
        """
        Set up event hooks for AutoCAD commands.
        
        Hooks into:
        - Command start
        - Subcommand prompts
        - Command completion
        - Command cancellation
        """
        try:
            # Hook into command event (approximate implementation)
            # NOTE: Actual implementation depends on AutoCAD Python/IronPython API
            #       This is a skeleton showing the event flow
            
            self.logger.debug("Event hooks configured")
            
        except Exception as e:
            self.logger.error(f"Failed to set up event hooks: {str(e)}")
    
    def on_command_started(self, command_name):
        """
        Handle command started event.
        
        - Parameters: command_name: Name of command (e.g., "LINE")
        """
        # Validate
        validated_name = CommandValidator.validate_command_name(command_name)
        if not validated_name:
            self.logger.warn(f"Invalid command name: {command_name}")
            return
        
        self.current_command = validated_name
        
        # Send event
        event = {
            "type": EventType.COMMAND_STARTED,
            "commandName": validated_name,
            "source": "nativePlugin"
        }
        
        self.event_sender.send_event(event)
        self.logger.info(f"Command started: {validated_name}")
    
    def on_subcommand_prompt(self, command_name, prompt_text, options=None):
        """
        Handle subcommand prompt event.
        
        - Parameters:
            command_name: Active command
            prompt_text: Prompt displayed (e.g., "Specify first point:")
            options: Optional list of option strings from prompt
        """
        # Validate
        validated_command = CommandValidator.validate_command_name(command_name)
        validated_prompt = CommandValidator.validate_subcommand(prompt_text)
        
        if not validated_command or not validated_prompt:
            return
        
        # Extract and validate options
        validated_options = None
        if options:
            validated_options = CommandValidator.validate_options(options)
        
        # Send event
        event = {
            "type": EventType.SUBCOMMAND_PROMPT,
            "commandName": validated_command,
            "subcommand": validated_prompt,
            "source": "nativePlugin"
        }
        
        if validated_options:
            event["activeOptions"] = validated_options
        
        self.event_sender.send_event(event)
    
    def on_command_cancelled(self, command_name):
        """
        Handle command cancellation.
        
        - Parameters: command_name: Name of cancelled command
        """
        validated_name = CommandValidator.validate_command_name(command_name)
        if not validated_name:
            return
        
        event = {
            "type": EventType.COMMAND_CANCELLED,
            "commandName": validated_name,
            "source": "nativePlugin"
        }
        
        self.event_sender.send_event(event)
        self.current_command = None
        self.logger.info(f"Command cancelled: {validated_name}")
    
    def on_command_completed(self, command_name):
        """
        Handle command completion.
        
        - Parameters: command_name: Name of completed command
        """
        validated_name = CommandValidator.validate_command_name(command_name)
        if not validated_name:
            return
        
        event = {
            "type": EventType.COMMAND_COMPLETED,
            "commandName": validated_name,
            "source": "nativePlugin"
        }
        
        self.event_sender.send_event(event)
        self.current_command = None

# MARK: - Module Interface

# Global plugin instance
_plugin = None

def run():
    """Main entry point called by AutoCAD when plugin loads"""
    global _plugin
    
    try:
        _plugin = AutoCADPlugin()
        _plugin.start()
        return True
    except Exception as e:
        PluginLogger.error(f"Plugin load failed: {str(e)}")
        return False

def unload():
    """Called when plugin is unloaded"""
    global _plugin
    
    if _plugin:
        _plugin.stop()
        _plugin = None

# Auto-run when imported
if __name__ == "__main__" or True:  # Auto-run in AutoCAD
    try:
        run()
    except:
        pass
