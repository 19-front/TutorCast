# TutorCastHelper.exe - Windows Implementation Guide

## Overview

**TutorCastHelper.exe** is a companion utility that runs inside a Windows VM (via Parallels Desktop) to enable AutoCAD command monitoring from macOS. It reads AutoCAD's UI via Windows UI Automation (UIA) and communicates the command state back to TutorCast over a local socket.

## Architecture

```
┌─────────────────────────────────────┐
│    macOS (TutorCast)                │
│    ParallelsWindowsAutoCADReader    │
│    Connects to 127.0.0.1:24680      │
└──────────┬──────────────────────────┘
           │ TCP Socket (local-only)
           ▼
┌─────────────────────────────────────┐
│    Windows VM (Parallels)           │
│    TutorCastHelper.exe              │
│    Listens on 127.0.0.1:24680       │
│    Reads AutoCAD via UIA            │
└─────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────┐
│    AutoCAD for Windows              │
│    UI Automation API                │
└─────────────────────────────────────┘
```

## Requirements

### Windows Side
- **Framework:** .NET Framework 4.7+ or .NET 6+
- **OS:** Windows 10, Windows 11
- **Dependencies:**
  - `System.Windows.Automation` (UIAutomation)
  - Sockets API (System.Net.Sockets)

### AutoCAD
- **Versions:** AutoCAD 2018 and later
- **Accessibility:** AutoCAD must have UI Automation exposed (default in modern versions)

## Implementation

### 1. Core Helper Structure

```csharp
class TutorCastHelper
{
    private const int PORT = 24680;
    private const string BIND_ADDRESS = "127.0.0.1";
    
    private TcpListener _listener;
    private Thread _serverThread;
    private bool _running = false;
    private AutoCADMonitor _monitor;
    
    public void Start()
    {
        _monitor = new AutoCADMonitor();
        _listener = new TcpListener(IPAddress.Parse(BIND_ADDRESS), PORT);
        _listener.Start();
        
        _serverThread = new Thread(AcceptConnections);
        _serverThread.IsBackground = true;
        _serverThread.Start();
        
        _running = true;
        Console.WriteLine($"TutorCastHelper listening on {BIND_ADDRESS}:{PORT}");
    }
    
    public void Stop()
    {
        _running = false;
        _listener?.Stop();
        _monitor?.Dispose();
    }
    
    private void AcceptConnections()
    {
        while (_running)
        {
            try
            {
                TcpClient client = _listener.AcceptTcpClient();
                Thread clientThread = new Thread(() => HandleClient(client));
                clientThread.IsBackground = true;
                clientThread.Start();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error accepting connection: {ex.Message}");
            }
        }
    }
    
    private void HandleClient(TcpClient client)
    {
        try
        {
            using (NetworkStream stream = client.GetStream())
            using (StreamReader reader = new StreamReader(stream))
            using (StreamWriter writer = new StreamWriter(stream) { AutoFlush = true })
            {
                // Set timeout for safety
                stream.ReadTimeout = 5000;
                stream.WriteTimeout = 5000;
                
                while (_running && client.Connected)
                {
                    string request = reader.ReadLine();
                    if (string.IsNullOrEmpty(request))
                        break;
                    
                    if (request == "GET_COMMAND_STATE")
                    {
                        var state = _monitor.GetCommandState();
                        string response = FormatResponse(state);
                        writer.WriteLine(response);
                    }
                }
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Client error: {ex.Message}");
        }
        finally
        {
            client?.Close();
        }
    }
    
    private string FormatResponse(CommandState state)
    {
        // JSON format for clarity
        var json = new Dictionary<string, string>
        {
            { "command", state.Command ?? "" },
            { "subcommand", state.Subcommand ?? "" }
        };
        
        var options = new JsonSerializerOptions { WriteIndented = false };
        return System.Text.Json.JsonSerializer.Serialize(json, options);
    }
    
    static void Main(string[] args)
    {
        TutorCastHelper helper = new TutorCastHelper();
        helper.Start();
        
        Console.WriteLine("TutorCastHelper running. Press Ctrl+C to exit.");
        Console.CancelKeyPress += (s, e) => 
        {
            e.Cancel = true;
            helper.Stop();
            Environment.Exit(0);
        };
        
        // Keep running
        Thread.Sleep(Timeout.Infinite);
    }
}
```

### 2. AutoCAD Monitor

```csharp
class AutoCADMonitor
{
    private Process _autoCADProcess;
    private AutomationElement _autoCADWindow;
    private PropertyWatcher _commandWatcher;
    
    public AutoCADMonitor()
    {
        FindAutoCAD();
    }
    
    private void FindAutoCAD()
    {
        try
        {
            // Search for AutoCAD window
            foreach (Process p in Process.GetProcesses())
            {
                if (p.ProcessName.Contains("acad"))
                {
                    _autoCADProcess = p;
                    _autoCADWindow = AutomationElement.FromHandle(p.MainWindowHandle);
                    Console.WriteLine($"Found AutoCAD: {p.ProcessName} (PID: {p.Id})");
                    return;
                }
            }
            Console.WriteLine("AutoCAD not found");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error finding AutoCAD: {ex.Message}");
        }
    }
    
    public CommandState GetCommandState()
    {
        try
        {
            if (_autoCADWindow == null || !_autoCADProcess?.IsRunning ?? false)
            {
                FindAutoCAD();
                return new CommandState { Command = "", Subcommand = "" };
            }
            
            string commandLine = ReadCommandLine();
            return ParseCommandState(commandLine);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error reading command state: {ex.Message}");
            return new CommandState { Command = "", Subcommand = "" };
        }
    }
    
    private string ReadCommandLine()
    {
        // Strategy: Find AutoCAD's command window / text display
        // Typically it's a read-only text field or label showing the command history
        
        try
        {
            var conditions = new AndCondition(
                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Window),
                new PropertyCondition(AutomationElement.NameProperty, null) // Any window
            );
            
            // Find text elements in AutoCAD window
            TreeWalker walker = TreeWalker.ControlViewWalker;
            AutomationElement element = walker.GetFirstChild(_autoCADWindow);
            
            StringBuilder commandText = new StringBuilder();
            int depth = 0;
            
            while (element != null && depth < 10)
            {
                try
                {
                    // Check if this is a text element
                    ControlType controlType = (ControlType)element.GetCurrentPropertyValue(
                        AutomationElement.ControlTypeProperty);
                    
                    if (controlType == ControlType.Text || controlType == ControlType.Edit)
                    {
                        string text = element.Current.Name;
                        if (!string.IsNullOrEmpty(text))
                        {
                            // Likely found command text
                            commandText.Append(text);
                            commandText.Append("\n");
                        }
                    }
                    
                    element = walker.GetNextSibling(element);
                }
                catch
                {
                    element = walker.GetNextSibling(element);
                }
                
                depth++;
            }
            
            return commandText.ToString().Trim();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error reading command line: {ex.Message}");
            return "";
        }
    }
    
    private CommandState ParseCommandState(string rawText)
    {
        // Same parsing logic as NativeMacOSAutoCADReader
        var lines = rawText.Split('\n', StringSplitOptions.RemoveEmptyEntries)
            .Select(l => l.Trim())
            .ToList();
        
        if (lines.Count == 0)
            return new CommandState { Command = "", Subcommand = "" };
        
        // Find command (all caps, 2-15 chars)
        string command = "";
        string subcommand = "";
        
        foreach (var line in lines)
        {
            if (IsLikelyCommand(line))
            {
                command = line;
                // Rest are subcommands
                int idx = lines.IndexOf(line);
                if (idx + 1 < lines.Count)
                    subcommand = string.Join(" ", lines.Skip(idx + 1));
                break;
            }
            
            // Try extracting command from prompt
            var parts = line.Split('-');
            if (parts.Length > 1 && IsLikelyCommand(parts[0]))
            {
                command = parts[0].Trim();
                subcommand = line;
                break;
            }
        }
        
        return new CommandState
        {
            Command = command,
            Subcommand = subcommand.Length > 100 ? 
                subcommand.Substring(0, 97) + "…" : 
                subcommand
        };
    }
    
    private bool IsLikelyCommand(string text)
    {
        if (string.IsNullOrEmpty(text) || text.Length < 2 || text.Length > 15)
            return false;
        
        int uppercase = text.Count(c => char.IsUpper(c));
        double ratio = (double)uppercase / text.Length;
        
        return ratio >= 0.7 && text.All(c => char.IsLetterOrDigit(c));
    }
    
    public void Dispose()
    {
        _autoCADProcess?.Dispose();
    }
}

struct CommandState
{
    public string Command { get; set; }
    public string Subcommand { get; set; }
}
```

### 3. Build & Distribution

**Project File (.csproj):**
```xml
<Project Sdk="Microsoft.NET.Sdk.WindowsDesktop">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net6.0-windows</TargetFramework>
    <UseWindowsForms>false</UseWindowsForms>
    <Nullable>enable</Nullable>
    <AssemblyName>TutorCastHelper</AssemblyName>
    <RuntimeIdentifiers>win-x64;win-x86</RuntimeIdentifiers>
    <SelfContained>true</SelfContained>
  </PropertyGroup>
  
  <ItemGroup>
    <Reference Include="UIAutomationClient" />
    <Reference Include="UIAutomationTypes" />
  </ItemGroup>
</Project>
```

**Build Command:**
```bash
dotnet build --configuration Release --runtime win-x64
```

**Output:** `TutorCastHelper.exe` (~50 MB single-file deployment)

### 4. Installation in Parallels

Copy `TutorCastHelper.exe` to:
```
Windows VM:  C:\Program Files\TutorCast\TutorCastHelper.exe
```

Create Windows Task Scheduler entry to auto-start:
```powershell
$action = New-ScheduledTaskAction -Execute "C:\Program Files\TutorCast\TutorCastHelper.exe"
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME
Register-ScheduledTask -TaskName "TutorCastHelper" -Action $action -Trigger $trigger -Principal $principal
```

## Protocol

### Request
```
GET_COMMAND_STATE\n
```

### Response
```json
{"command":"LINE","subcommand":"Specify first point:"}
```

or

```
LINE\nSpecify first point:\n
```

### Timeouts
- Socket: 2 seconds (per macOS reader)
- UI Automation: 1 second per element search
- Overall request: 5 seconds max

## Error Handling

### AutoCAD Not Running
```json
{"command":"","subcommand":""}
```

### UI Automation Failure
```json
{"command":"ERROR","subcommand":"UIAutomation unavailable"}
```

### Command Window Not Found
```json
{"command":"","subcommand":""}
```

## Deployment Options

### Option 1: Include with macOS App
- Bundle `TutorCastHelper.exe` in macOS app
- Copy to shared folder during setup
- Parallels auto-mounts shared folders
- Helper auto-starts via Task Scheduler

### Option 2: Separate Download
- Host on GitHub Releases
- Guide user to download and install in Windows
- More manual but simpler for distribution

### Option 3: Parallels Shared Folder
- Store in `/Volumes/Parallels\ Shared\ Folders/...`
- Reference directly from Windows mount point
- Most transparent to user

## Testing

### Unit Tests
```csharp
[TestClass]
public class CommandParsingTests
{
    [TestMethod]
    public void ParseLineCommand()
    {
        var monitor = new AutoCADMonitor();
        var result = monitor.ParseCommandState("LINE");
        Assert.AreEqual("LINE", result.Command);
    }
    
    [TestMethod]
    public void ParseCommandWithPrompt()
    {
        var monitor = new AutoCADMonitor();
        var result = monitor.ParseCommandState(
            "LINE\nSpecify first point:");
        Assert.AreEqual("LINE", result.Command);
        Assert.AreEqual("Specify first point:", result.Subcommand);
    }
}
```

### Integration Tests
1. Start TutorCastHelper.exe
2. Connect from macOS: `nc localhost 24680`
3. Send: `GET_COMMAND_STATE`
4. Verify JSON response

### Manual Testing
1. Run AutoCAD in Windows VM
2. Run TutorCastHelper.exe
3. Type "L" in AutoCAD
4. Query helper → should return "LINE"

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Port already in use | Another instance running | Check `netstat -an` |
| AutoCAD not found | Process name mismatch | Check AutoCAD version, process name may be `acad.exe`, `acadlt.exe` |
| UI Automation fails | Requires admin? | Run helper as administrator |
| No response from socket | Helper crashed | Check Windows Event Viewer |
| Command always empty | Parsing error | Add debug logging to `ParseCommandState()` |

## Future Improvements

1. **Auto-launch:** Detect when Parallels starts and auto-launch helper
2. **Debugging UI:** Visual debug window showing detected commands
3. **Configuration file:** Allow custom port, AutoCAD path
4. **Logging:** File-based logging for troubleshooting
5. **Auto-update:** Self-updating from GitHub
6. **Multi-AutoCAD:** Support multiple AutoCAD instances

---

**Status:** 🔴 Not yet implemented
**Priority:** Medium (Parallels support is secondary to native macOS)
**Effort:** 3-4 days for C# developer
