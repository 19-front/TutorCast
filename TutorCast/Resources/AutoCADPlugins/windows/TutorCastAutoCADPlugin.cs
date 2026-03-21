// TutorCastAutoCADPlugin.cs
// AutoCAD for Windows .NET Plugin (runs in Parallels Windows VM)
// 
// Intercepts command events and forwards to TutorCast on the macOS host
// via TCP socket (primary) or shared folder (fallback).
//
// Build Target: .NET Framework 4.8 (matches AutoCAD's .NET runtime)
// References:
//   - Autodesk.AutoCAD.ApplicationServices.dll
//   - Autodesk.AutoCAD.DatabaseServices.dll
//   - Autodesk.AutoCAD.EditorInput.dll
//   - Autodesk.AutoCAD.Runtime.dll
//
// Installation:
// 1. Build to TutorCastPlugin.dll
// 2. Copy to C:\Program Files\Autodesk\AutoCAD <year>\
//    OR deploy via AutoCAD .bundle plugin format
// 3. AutoCAD loads on startup

using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.Runtime;
using Autodesk.AutoCAD.EditorInput;

[assembly: CommandClass(typeof(TutorCast.TutorCastAutoCADPlugin))]
[assembly: ExtensionApplication(typeof(TutorCast.TutorCastAutoCADPlugin))]

namespace TutorCast
{
    /// <summary>
    /// TutorCastAutoCADPlugin — AutoCAD for Windows .NET extension
    /// 
    /// Sends command events to TutorCast running on the macOS host machine
    /// via TCP socket at 10.211.55.2:19848 (Parallels host IP).
    /// Fallback: writes to shared folder ~/tutorcast_events/
    /// </summary>
    public class TutorCastAutoCADPlugin : IExtensionApplication
    {
        // ====================================================================
        // Configuration
        // ====================================================================
        
        private const int HostPort = 19848;
        
        /// <summary>
        /// Parallels Default and Shared adapter host IPs (always reachable from VM)
        /// </summary>
        private static readonly string[] HostIPs = {
            "10.211.55.2",    // Primary: Parallels Default adapter host IP
            "10.37.129.2",    // Fallback: Parallels Shared adapter host IP
        };
        
        /// <summary>
        /// Path to shared folder (maps to ~/tutorcast_events/ on macOS)
        /// </summary>
        private static string SharedFolderPath => Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
            "Parallels Shared Folders", "Home", "tutorcast_events"
        );
        
        // ====================================================================
        // Instance State
        // ====================================================================
        
        private TcpClient _tcpClient;
        private NetworkStream _stream;
        private readonly object _lock = new object();
        private string _currentCommand = "";
        private Timer _reconnectTimer;
        private Document _lastActiveDoc;
        
        // ====================================================================
        // IExtensionApplication Implementation
        // ====================================================================
        
        /// <summary>
        /// Called when AutoCAD loads this plugin
        /// </summary>
        public void Initialize()
        {
            try
            {
                // Ensure shared folder fallback exists
                Directory.CreateDirectory(SharedFolderPath);
                
                // Subscribe to document collection events (new/existing documents)
                Application.DocumentManager.DocumentCreated += OnDocumentCreated;
                
                // Subscribe to existing documents
                foreach (Document doc in Application.DocumentManager)
                {
                    SubscribeToDocument(doc);
                }
                
                // Start TCP connection to macOS host
                ConnectAsync();
                
                SystemDebugPrint("[TutorCast] Plugin initialized. Listening for AutoCAD commands.");
            }
            catch (Exception ex)
            {
                SystemDebugPrint($"[TutorCast] Initialization error: {ex.Message}");
            }
        }
        
        /// <summary>
        /// Called when AutoCAD unloads this plugin
        /// </summary>
        public void Terminate()
        {
            try
            {
                lock (_lock)
                {
                    _stream?.Close();
                    _tcpClient?.Close();
                    _stream = null;
                    _tcpClient = null;
                }
                
                _reconnectTimer?.Dispose();
                
                SystemDebugPrint("[TutorCast] Plugin terminated.");
            }
            catch (Exception ex)
            {
                SystemDebugPrint($"[TutorCast] Termination error: {ex.Message}");
            }
        }
        
        // ====================================================================
        // Document Event Subscriptions
        // ====================================================================
        
        private void OnDocumentCreated(object sender, DocumentCollectionEventArgs e)
        {
            SubscribeToDocument(e.Document);
        }
        
        private void SubscribeToDocument(Document doc)
        {
            try
            {
                _lastActiveDoc = doc;
                
                // Command event handlers
                doc.CommandWillStart += OnCommandWillStart;
                doc.CommandEnded += OnCommandEnded;
                doc.CommandCancelled += OnCommandCancelled;
                doc.CommandFailed += OnCommandFailed;
                
                // Editor (prompt) event handlers
                var ed = doc.Editor;
                ed.PromptedForString += OnPrompted;
                ed.PromptedForInteger += OnPrompted;
                ed.PromptedForReal += OnPrompted;
                ed.PromptedForPoint += OnPrompted;
                ed.PromptedForKeyword += OnPrompted;
                ed.PromptedForSelection += OnPrompted;
                ed.PromptedForDistance += OnPrompted;
                ed.PromptedForAngle += OnPrompted;
            }
            catch { }
        }
        
        // ====================================================================
        // Command Event Handlers
        // ====================================================================
        
        private void OnCommandWillStart(object sender, CommandEventArgs e)
        {
            _currentCommand = e.GlobalCommandName;
            SendEvent("commandStarted", e.GlobalCommandName, null, null);
        }
        
        private void OnCommandEnded(object sender, CommandEventArgs e)
        {
            SendEvent("commandCompleted", e.GlobalCommandName, null, null);
            _currentCommand = "";
        }
        
        private void OnCommandCancelled(object sender, CommandEventArgs e)
        {
            SendEvent("commandCancelled", e.GlobalCommandName, null, null);
            _currentCommand = "";
        }
        
        private void OnCommandFailed(object sender, CommandEventArgs e)
        {
            SendEvent("commandCancelled", e.GlobalCommandName, null, null);
            _currentCommand = "";
        }
        
        // ====================================================================
        // Editor Prompt Handlers (subcommands/options)
        // ====================================================================
        
        private void OnPrompted(object sender, EventArgs e)
        {
            // Called when editor prompts for input (point, string, keyword, etc.)
            if (string.IsNullOrEmpty(_currentCommand)) return;
            
            try
            {
                var doc = Application.DocumentManager.MdiActiveDocument;
                if (doc == null) return;
                
                var ed = doc.Editor;
                
                // Extract prompt text from the editor's internal state
                string promptText = ExtractCurrentPrompt(ed, e);
                if (string.IsNullOrEmpty(promptText)) return;
                
                var (subcommand, options) = ParsePrompt(promptText);
                SendEvent("subcommandPrompt", _currentCommand, subcommand, options);
            }
            catch { }
        }
        
        // ====================================================================
        // Prompt Text Extraction
        // ====================================================================
        
        /// <summary>
        /// Extract the current prompt text from the editor
        /// 
        /// Note: AutoCAD .NET API does not directly expose command line text.
        /// This method attempts to extract it from event context or provides
        /// a reasonable fallback. In production, you may need to use reflection
        /// or hook into LISP (vlisp-call) to get precise prompt text.
        /// </summary>
        private static string ExtractCurrentPrompt(Editor ed, EventArgs e)
        {
            try
            {
                // Method 1: Check if this is a PromptedForKeyword event (has options)
                if (e is PromptedForKeywordEventArgs kw)
                {
                    // Keyword event contains the prompt context
                    return kw.PromptContext != null
                        ? "Select an option"
                        : "";
                }
                
                // Method 2: Check if this is a PromptedForSelection event
                if (e is PromptedForSelectionEventArgs sel)
                {
                    return "Select objects";
                }
                
                // Method 3: Check if this is a PromptedForPoint event
                if (e is PromptedForPointEventArgs pt)
                {
                    return "Specify point";
                }
                
                // Fallback: generic prompt
                return "Specify value";
            }
            catch
            {
                return "";
            }
        }
        
        // ====================================================================
        // Prompt Parsing
        // ====================================================================
        
        private static (string subcommand, string[] options) ParsePrompt(string text)
        {
            if (string.IsNullOrEmpty(text))
                return ("", Array.Empty<string>());
            
            // Extract text before first "[" as the subcommand prompt
            int bracketIdx = text.IndexOf('[');
            string subcommand = bracketIdx > 0
                ? text.Substring(0, bracketIdx).Trim().TrimEnd(':').Trim()
                : text.Trim().TrimEnd(':').Trim();
            
            // Extract options from [Option1/Option2/Option3]
            var options = new List<string>();
            int start = text.IndexOf('[');
            int end = text.IndexOf(']');
            
            if (start >= 0 && end > start)
            {
                string inner = text.Substring(start + 1, end - start - 1);
                var opts = inner.Split(new[] { '/' }, StringSplitOptions.RemoveEmptyEntries);
                foreach (var opt in opts)
                {
                    options.Add(opt.Trim());
                }
            }
            
            return (subcommand, options.ToArray());
        }
        
        // ====================================================================
        // Event Transmission
        // ====================================================================
        
        /// <summary>
        /// Send an AutoCADCommandEvent to TutorCast (JSON format)
        /// Primary: TCP socket
        /// Fallback: shared folder file write
        /// </summary>
        private void SendEvent(string type, string commandName, string subcommand, string[] options)
        {
            try
            {
                var payload = new
                {
                    type,
                    commandName = (commandName ?? "").ToUpper().Trim(),
                    subcommand,
                    activeOptions = options,
                    selectedOption = (string)null,
                    rawCommandLineText = (string)null,
                    timestamp = DateTime.UtcNow.ToString("o"),  // ISO 8601
                    source = "parallelsPlugin"
                };
                
                string json = JsonSerializer.Serialize(payload) + "\n";
                
                // Try TCP first
                if (!TrySendTcp(json))
                {
                    // Fallback: write to shared folder
                    WriteFallback(json);
                }
            }
            catch { }
        }
        
        private bool TrySendTcp(string json)
        {
            lock (_lock)
            {
                if (_stream == null)
                    return false;
                
                try
                {
                    byte[] data = Encoding.UTF8.GetBytes(json);
                    _stream.Write(data, 0, data.Length);
                    _stream.Flush();
                    return true;
                }
                catch (Exception ex)
                {
                    SystemDebugPrint($"[TutorCast] TCP send failed: {ex.Message}");
                    
                    // Close broken connection
                    try
                    {
                        _stream?.Close();
                        _tcpClient?.Close();
                    }
                    catch { }
                    
                    _stream = null;
                    _tcpClient = null;
                    ScheduleReconnect();
                    return false;
                }
            }
        }
        
        private void WriteFallback(string json)
        {
            try
            {
                string filename = $"event_{DateTime.UtcNow:yyyyMMddHHmmssfff}.json";
                string path = Path.Combine(SharedFolderPath, filename);
                
                File.WriteAllText(path, json, Encoding.UTF8);
                SystemDebugPrint($"[TutorCast] Event written to shared folder: {filename}");
            }
            catch (Exception ex)
            {
                SystemDebugPrint($"[TutorCast] Shared folder write failed: {ex.Message}");
            }
        }
        
        // ====================================================================
        // TCP Connection Management
        // ====================================================================
        
        private void ConnectAsync()
        {
            Task.Run(() =>
            {
                foreach (var ip in HostIPs)
                {
                    try
                    {
                        SystemDebugPrint($"[TutorCast] Attempting connection to {ip}:{HostPort}...");
                        
                        var client = new TcpClient { ReceiveBufferSize = 65536 };
                        client.Connect(ip, HostPort);
                        
                        lock (_lock)
                        {
                            _tcpClient = client;
                            _stream = client.GetStream();
                        }
                        
                        SystemDebugPrint($"[TutorCast] ✓ Connected to {ip}:{HostPort}");
                        return;  // Success
                    }
                    catch (Exception ex)
                    {
                        SystemDebugPrint($"[TutorCast] Connection to {ip} failed: {ex.Message}");
                    }
                }
                
                SystemDebugPrint("[TutorCast] All connection attempts failed. Will retry in 5 seconds.");
                ScheduleReconnect();
            });
        }
        
        private void ScheduleReconnect()
        {
            _reconnectTimer?.Dispose();
            _reconnectTimer = new Timer(
                _ => ConnectAsync(),
                null,
                5000,  // Delay: 5 seconds
                Timeout.Infinite  // No repeat
            );
        }
        
        // ====================================================================
        // Debugging
        // ====================================================================
        
        private static void SystemDebugPrint(string message)
        {
            try
            {
                // Write to Windows Event Log or debug console
                System.Diagnostics.Debug.WriteLine(message);
            }
            catch { }
        }
    }
}
