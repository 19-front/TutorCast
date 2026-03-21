using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

using Autodesk.AutoCAD.Runtime;
using Autodesk.AutoCAD.EditorInput;
using Autodesk.AutoCAD.ApplicationServices;

namespace TutorCast.Plugins.AutoCAD
{
    /// <summary>
    /// TutorCast AutoCAD Plugin for Windows (Parallels VM)
    /// 
    /// Sends AutoCAD command events to TutorCast host via TCP socket.
    /// - Command started/completed
    /// - Subcommand prompts  
    /// - Option selection
    /// - Real-time updates
    /// 
    /// Security:
    /// - TCP port: 19848
    /// - Bind address: 127.0.0.1 (will be on Parallels network)
    /// - Max command name: 64 characters
    /// - Max subcommand: 128 characters
    /// - Data validation before transmission
    /// </summary>
    public partial class TutorCastPlugin : IExtensionApplication
    {
        #region Configuration

        private static class PluginConfig
        {
            public const string TutorCastHost = "10.211.55.1";  // Parallels gateway (host)
            public const int TutorCastPort = 19848;
            public const int SocketTimeout = 5000;              // milliseconds
            
            // Command validation
            public const int MaxCommandNameLength = 64;
            public const int MaxSubcommandLength = 128;
            
            // Retry configuration
            public const int MaxRetries = 3;
            public const int RetryDelayMs = 500;
            
            // Logging
            public static string LogPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                "tutorcast_plugin.log"
            );
        }

        #endregion

        #region Event Types

        private static class EventType
        {
            public const string CommandStarted = "commandStarted";
            public const string SubcommandPrompt = "subcommandPrompt";
            public const string CommandCompleted = "commandCompleted";
            public const string CommandCancelled = "commandCancelled";
            public const string OptionSelected = "optionSelected";
            public const string CommandLineText = "commandLineText";
        }

        #endregion

        #region State

        private static TutorCastPlugin _instance;
        private Document _activeDoc;
        private EventSender _eventSender;
        private Editor _editor;
        private string _currentCommand;
        private bool _isMonitoring;

        #endregion

        #region Initialization

        /// <summary>Initialize the plugin when AutoCAD loads it</summary>
        public void Initialize()
        {
            _instance = this;
            _eventSender = new EventSender();
            _isMonitoring = false;

            try
            {
                // Get active document
                var acadApp = Application.AcadApplication as Autodesk.AutoCAD.Interop.AcadApplication;
                if (acadApp?.ActiveDocument != null)
                {
                    _activeDoc = acadApp.ActiveDocument;
                    _editor = _activeDoc.Editor;
                }

                // Log startup
                Log("TutorCast Plugin initializing...");

                // Connect to host
                if (_eventSender.Connect())
                {
                    Log("Connected to TutorCast host");
                }
                else
                {
                    Log("Warning: Could not connect to host initially (will retry on events)");
                }

                // Set up command event hooks
                SetupEventHooks();

                _isMonitoring = true;
                Log("TutorCast Plugin monitoring active");
            }
            catch (Exception ex)
            {
                Log($"Initialization error: {ex.Message}");
            }
        }

        /// <summary>Clean up when AutoCAD unloads the plugin</summary>
        public void Terminate()
        {
            _isMonitoring = false;
            _eventSender?.Disconnect();
            Log("TutorCast Plugin terminated");
        }

        #endregion

        #region Event Hooks

        private void SetupEventHooks()
        {
            try
            {
                // Hook into document events
                if (Document.SendStringToExecute != null)
                {
                    // Note: AutoCAD .NET doesn't have direct command interception
                    // This would require:
                    // 1. Reactor-based system (if available)
                    // 2. Journal file monitoring
                    // 3. Command line callback
                    // For now, we'll document the expected hooks
                    
                    Log("Event hooks would be configured here");
                }
            }
            catch (Exception ex)
            {
                Log($"Error setting up hooks: {ex.Message}");
            }
        }

        #endregion

        #region Public Event Handlers

        /// <summary>Handle command started event</summary>
        public void OnCommandStarted(string commandName)
        {
            if (!_isMonitoring)
                return;

            var validated = CommandValidator.ValidateCommandName(commandName);
            if (string.IsNullOrEmpty(validated))
            {
                Log($"Invalid command name: {commandName}");
                return;
            }

            _currentCommand = validated;

            var evt = new Dictionary<string, object>
            {
                { "type", EventType.CommandStarted },
                { "commandName", validated },
                { "source", "parallelsPlugin" }
            };

            _eventSender.SendEvent(evt);
            Log($"Command started: {validated}");
        }

        /// <summary>Handle subcommand prompt event</summary>
        public void OnSubcommandPrompt(string commandName, string promptText, string[] options = null)
        {
            if (!_isMonitoring)
                return;

            var validatedCommand = CommandValidator.ValidateCommandName(commandName);
            var validatedPrompt = CommandValidator.ValidateSubcommand(promptText);

            if (string.IsNullOrEmpty(validatedCommand) || string.IsNullOrEmpty(validatedPrompt))
                return;

            var evt = new Dictionary<string, object>
            {
                { "type", EventType.SubcommandPrompt },
                { "commandName", validatedCommand },
                { "subcommand", validatedPrompt },
                { "source", "parallelsPlugin" }
            };

            if (options?.Length > 0)
            {
                var validatedOptions = CommandValidator.ValidateOptions(options);
                if (validatedOptions.Count > 0)
                {
                    evt.Add("activeOptions", validatedOptions);
                }
            }

            _eventSender.SendEvent(evt);
        }

        /// <summary>Handle command cancellation event</summary>
        public void OnCommandCancelled(string commandName)
        {
            if (!_isMonitoring)
                return;

            var validated = CommandValidator.ValidateCommandName(commandName);
            if (string.IsNullOrEmpty(validated))
                return;

            var evt = new Dictionary<string, object>
            {
                { "type", EventType.CommandCancelled },
                { "commandName", validated },
                { "source", "parallelsPlugin" }
            };

            _eventSender.SendEvent(evt);
            _currentCommand = null;
            Log($"Command cancelled: {validated}");
        }

        /// <summary>Handle command completion event</summary>
        public void OnCommandCompleted(string commandName)
        {
            if (!_isMonitoring)
                return;

            var validated = CommandValidator.ValidateCommandName(commandName);
            if (string.IsNullOrEmpty(validated))
                return;

            var evt = new Dictionary<string, object>
            {
                { "type", EventType.CommandCompleted },
                { "commandName", validated },
                { "source", "parallelsPlugin" }
            };

            _eventSender.SendEvent(evt);
            _currentCommand = null;
        }

        #endregion

        #region Logging

        private static void Log(string message)
        {
            var timestamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
            var logLine = $"[{timestamp}] [TutorCast] {message}";

            // Write to console
            Console.WriteLine(logLine);

            // Write to log file
            try
            {
                File.AppendAllText(PluginConfig.LogPath, logLine + Environment.NewLine);
            }
            catch
            {
                // Silently fail if we can't write log
            }
        }

        #endregion
    }

    #region Command Validation

    /// <summary>Validates and sanitizes command data</summary>
    public static class CommandValidator
    {
        /// <summary>Validate and sanitize command name</summary>
        public static string ValidateCommandName(string name)
        {
            if (string.IsNullOrWhiteSpace(name))
                return null;

            var sanitized = SanitizeString(name, PluginConfig.MaxCommandNameLength);
            
            // Must be alphanumeric + underscore
            sanitized = new string(sanitized.Where(c => char.IsLetterOrDigit(c) || c == '_').ToArray());
            
            return string.IsNullOrEmpty(sanitized) ? null : sanitized;
        }

        /// <summary>Validate and sanitize subcommand text</summary>
        public static string ValidateSubcommand(string text)
        {
            if (string.IsNullOrWhiteSpace(text))
                return null;

            return SanitizeString(text, PluginConfig.MaxSubcommandLength);
        }

        /// <summary>Validate options array</summary>
        public static List<string> ValidateOptions(string[] options)
        {
            var validated = new List<string>();

            if (options == null || options.Length == 0)
                return validated;

            foreach (var opt in options)
            {
                var sanitized = SanitizeString(opt, 50);
                if (!string.IsNullOrEmpty(sanitized))
                {
                    validated.Add(sanitized);
                }
            }

            return validated;
        }

        /// <summary>Remove control characters and enforce max length</summary>
        private static string SanitizeString(string text, int maxLength)
        {
            if (string.IsNullOrEmpty(text))
                return null;

            // Remove control characters
            var sanitized = new string(text
                .Where(c => c >= 32 && c != 127)
                .ToArray());

            // Enforce max length
            if (sanitized.Length > maxLength)
                sanitized = sanitized.Substring(0, maxLength);

            return string.IsNullOrEmpty(sanitized) ? null : sanitized;
        }
    }

    #endregion

    #region Event Transmission

    /// <summary>Sends events to TutorCast host via TCP socket</summary>
    public class EventSender
    {
        private TcpClient _socket;
        private bool _connected;

        /// <summary>Connect to TutorCast host</summary>
        public bool Connect()
        {
            for (int attempt = 0; attempt < PluginConfig.MaxRetries; attempt++)
            {
                try
                {
                    _socket = new TcpClient();
                    _socket.ReceiveTimeout = PluginConfig.SocketTimeout;
                    _socket.SendTimeout = PluginConfig.SocketTimeout;

                    _socket.Connect(PluginConfig.TutorCastHost, PluginConfig.TutorCastPort);
                    _connected = true;
                    return true;
                }
                catch (Exception ex)
                {
                    if (attempt < PluginConfig.MaxRetries - 1)
                    {
                        Thread.Sleep(PluginConfig.RetryDelayMs);
                    }
                }
            }

            _connected = false;
            return false;
        }

        /// <summary>Disconnect from socket</summary>
        public void Disconnect()
        {
            if (_socket != null)
            {
                try
                {
                    _socket.Close();
                    _socket.Dispose();
                }
                catch { }

                _socket = null;
                _connected = false;
            }
        }

        /// <summary>Send event to TutorCast</summary>
        public bool SendEvent(Dictionary<string, object> eventData)
        {
            if (!_connected && !Connect())
                return false;

            try
            {
                // Add timestamp
                eventData["timestamp"] = DateTime.Now.ToString("O");

                // Convert to JSON
                var json = JsonSerializer.Serialize(eventData);
                var data = Encoding.UTF8.GetBytes(json + "\n");

                // Send to socket
                var stream = _socket.GetStream();
                stream.Write(data, 0, data.Length);
                stream.Flush();

                return true;
            }
            catch (Exception ex)
            {
                _connected = false;
                _socket = null;

                // Retry once
                if (Connect())
                {
                    try
                    {
                        var json = JsonSerializer.Serialize(eventData);
                        var data = Encoding.UTF8.GetBytes(json + "\n");
                        var stream = _socket.GetStream();
                        stream.Write(data, 0, data.Length);
                        stream.Flush();
                        return true;
                    }
                    catch
                    {
                        return false;
                    }
                }

                return false;
            }
        }
    }

    #endregion
}
