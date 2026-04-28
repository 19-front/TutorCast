# TutorCast Event Format & API Reference

## Overview

TutorCast communicates with AutoCAD plugins using **JSON-formatted events** over **TCP/Unix sockets**.

- **Protocol:** TCP (Parallels) / Unix Socket (Native macOS)
- **Port:** 19848 (Parallels)
- **Socket:** `/tmp/tutorcast_autocad.sock` (Native macOS)
- **Format:** JSON, newline-delimited
- **Encoding:** UTF-8

---

## Event Structure

All events follow this base structure:

```json
{
  "type": "commandStarted|subcommandPrompt|optionSelected|commandCompleted|commandCancelled|commandLineText",
  "commandName": "LINE",
  "subcommand": "Specify first point:",
  "activeOptions": ["Through", "Erase", "Layer"],
  "selectedOption": "Through",
  "rawCommandLineText": "LINE Specify first point:",
  "timestamp": "2026-03-21T14:30:00Z",
  "checksum": "a3f5b9e2..."
}
```

---

## Event Types

### 1. commandStarted
**Fired:** When user starts a new AutoCAD command

```json
{
  "type": "commandStarted",
  "commandName": "LINE",
  "timestamp": "2026-03-21T14:30:00Z",
  "checksum": "a3f5b9e2c8d1e4f7..."
}
```

**Overlay Response:**
- Displays abbreviated command name (e.g., `LIN`)
- Shows color from profile mapping
- Duration: 5 seconds

**TutorCast Processing:**
```swift
case .commandStarted:
    let label = labelForCommand(event.commandName)  // "LINE" → "LIN"
    currentLabel = label.short
    secondaryLabel = label.full
    colorCategory = colorForCommand(event.commandName)
    scheduleCommandEventClear(duration: 5.0)
```

---

### 2. subcommandPrompt
**Fired:** When AutoCAD prompts for subcommand or option

```json
{
  "type": "subcommandPrompt",
  "commandName": "OFFSET",
  "subcommand": "Select object to offset:",
  "activeOptions": ["Through", "Erase", "Layer"],
  "timestamp": "2026-03-21T14:30:05Z",
  "checksum": "b4g6c0f3d9e2f5h8..."
}
```

**Overlay Response:**
- Updates secondary label with prompt
- Shows abbreviated options (first 3)
- Duration: 8 seconds

**TutorCast Processing:**
```swift
case .subcommandPrompt:
    let formatted = formatSubcommandPrompt(
        event.subcommand,
        options: event.activeOptions
    )
    secondaryLabel = formatted  // "Select object... [Through/Erase/Layer]"
    scheduleCommandEventClear(duration: 8.0)
```

---

### 3. optionSelected
**Fired:** When user selects an option

```json
{
  "type": "optionSelected",
  "commandName": "OFFSET",
  "selectedOption": "Through",
  "timestamp": "2026-03-21T14:30:08Z",
  "checksum": "c5h7d1g4e0f3h6i9..."
}
```

**Overlay Response:**
- Flashes selected option briefly
- Duration: 2 seconds

**TutorCast Processing:**
```swift
case .optionSelected:
    secondaryLabel = event.selectedOption ?? ""
    scheduleCommandEventClear(duration: 2.0)
```

---

### 4. commandCompleted
**Fired:** When command successfully completes

```json
{
  "type": "commandCompleted",
  "commandName": "LINE",
  "timestamp": "2026-03-21T14:30:10Z",
  "checksum": "d6i8e2h5f1g4i7j0..."
}
```

**Overlay Response:**
- Fades out quickly
- Returns to "Ready"
- Duration: 0.8 seconds

**TutorCast Processing:**
```swift
case .commandCompleted, .commandCancelled:
    scheduleCommandEventClear(duration: 0.8)
```

---

### 5. commandCancelled
**Fired:** When user cancels command (ESC key)

```json
{
  "type": "commandCancelled",
  "commandName": "HATCH",
  "timestamp": "2026-03-21T14:30:15Z",
  "checksum": "e7j9f3i6g2h5j8k1..."
}
```

**Same behavior as commandCompleted**

---

### 6. commandLineText
**Fired:** Raw command line text (fallback)

```json
{
  "type": "commandLineText",
  "rawCommandLineText": "LINE Specify first point:",
  "timestamp": "2026-03-21T14:30:00Z",
  "checksum": "f8k0g4j7h3i6k9l2..."
}
```

**Used when:** Structured event data unavailable

**Overlay Response:**
- Sanitized and displayed as-is
- Duration: 2 seconds

---

## Field Reference

### Common Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | ✓ | Event type from list above |
| `timestamp` | ISO8601 | ✓ | UTC timestamp of event |
| `checksum` | string | ✓ | SHA-256 hash for validation |

### Command Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `commandName` | string | ✗ | Current AutoCAD command (e.g., "LINE", "OFFSET") |
| `subcommand` | string | ✗ | Current prompt/subcommand text |
| `activeOptions` | array | ✗ | Available options user can select |
| `selectedOption` | string | ✗ | Option user selected |
| `rawCommandLineText` | string | ✗ | Raw command line text |

### Validation Rules

- `commandName`: 3-64 chars, alphanumeric + underscore
- `subcommand`: Max 128 chars, no control characters
- `activeOptions`: Max 10 options, 64 chars each
- `rawCommandLineText`: Max 256 chars

---

## Checksum Validation

Events include SHA-256 checksum for integrity:

```swift
// Plugin (Windows) calculates:
let jsonString = #"{"type":"commandStarted","commandName":"LINE"}"#
let data = jsonString.data(using: .utf8)!
let digest = SHA256.hash(data: data)
let checksum = digest.map { String(format: "%02x", $0) }.joined()
// Result: "a3f5b9e2c8d1e4f7..."

// TutorCast (macOS) verifies:
if verifyChecksum(event, expectedChecksum: receivedChecksum) {
    processEvent(event)  // ✓ Valid
} else {
    log.warning("Checksum mismatch - event rejected")  // ✗ Invalid
}
```

---

## Send Format

### TCP Connection (Parallels)

```
1. Plugin initiates TCP connection to 192.168.1.100:19848
2. TutorCast accepts connection
3. Plugin sends JSON-formatted events
4. Events are newline-delimited
5. Connection remains open for event stream
```

**Example transmission:**
```
{"type":"commandStarted","commandName":"LINE","timestamp":"2026-03-21T14:30:00Z","checksum":"a3f5..."}\n
{"type":"subcommandPrompt","commandName":"LINE","subcommand":"Specify first point:","timestamp":"2026-03-21T14:30:01Z","checksum":"b4g6..."}\n
{"type":"commandCompleted","commandName":"LINE","timestamp":"2026-03-21T14:30:10Z","checksum":"d6i8..."}\n
```

### Unix Socket Connection (Native macOS)

```
1. Plugin connects to /tmp/tutorcast_autocad.sock
2. TutorCast accepts connection
3. Same JSON event format
4. Events are newline-delimited
5. Connection remains open
```

---

## Response Codes

TutorCast sends back HTTP-like status for each event:

```
200 OK                   - Event accepted and processed
400 Bad Format           - JSON parsing failed
401 Invalid Checksum     - Security validation failed
403 Rejected             - Content policy violation
408 Timeout              - Connection timeout
429 Rate Limited         - Too many events
500 Internal Error       - Processing error
```

**Response format:**
```
STATUS CODE\nERROR_MESSAGE\n
```

**Example:**
```
400\nInvalid JSON format: missing 'type' field\n
```

---

## Event Lifecycle

```
┌─────────────────────┐
│  Plugin Detects     │
│  AutoCAD Event      │
└──────────┬──────────┘
           │
           ↓
┌─────────────────────┐
│  Format as JSON     │
│  Calculate Checksum │
└──────────┬──────────┘
           │
           ↓
┌─────────────────────┐
│  Send via TCP/Unix  │
│  (newline-delimited)│
└──────────┬──────────┘
           │
           ↓
┌─────────────────────┐
│  TutorCast Receives │
│  Parses JSON        │
└──────────┬──────────┘
           │
           ↓
┌─────────────────────┐
│  SecurityValidator  │
│  • Verify Checksum  │
│  • Validate Format  │
│  • Check Limits     │
└──────────┬──────────┘
           │
           ├─── REJECT ──→ Log Error, Send 4xx
           │
           ├─── ACCEPT
           │
           ↓
┌─────────────────────┐
│  LabelEngine        │
│  Process Event      │
│  Update Label Text  │
│  Schedule Clear     │
└──────────┬──────────┘
           │
           ↓
┌─────────────────────┐
│  OverlayContentView │
│  Display Update     │
│  Animate Transition │
└─────────────────────┘
```

---

## Examples

### Example 1: Simple Command Flow

```
USER: Types "LINE" in AutoCAD

EVENT 1 (commandStarted):
{
  "type": "commandStarted",
  "commandName": "LINE",
  "timestamp": "2026-03-21T14:30:00Z",
  "checksum": "a3f5b9e2..."
}
DISPLAY: "LIN" appears, blue color, 5s duration

EVENT 2 (subcommandPrompt):
{
  "type": "subcommandPrompt",
  "commandName": "LINE",
  "subcommand": "Specify first point:",
  "timestamp": "2026-03-21T14:30:01Z",
  "checksum": "b4g6c0f3..."
}
DISPLAY: Secondary shows "Specify first point:", 8s duration

EVENT 3 (commandCompleted):
{
  "type": "commandCompleted",
  "commandName": "LINE",
  "timestamp": "2026-03-21T14:30:10Z",
  "checksum": "d6i8e2h5..."
}
DISPLAY: Fades out to "Ready", 0.8s duration
```

### Example 2: Command with Options

```
USER: Types "OFFSET", selects "Through" option

EVENT 1 (commandStarted):
{
  "type": "commandStarted",
  "commandName": "OFFSET",
  "timestamp": "2026-03-21T14:31:00Z",
  "checksum": "..."
}
DISPLAY: "OFF"

EVENT 2 (subcommandPrompt):
{
  "type": "subcommandPrompt",
  "commandName": "OFFSET",
  "subcommand": "Select object to offset:",
  "activeOptions": ["Through", "Erase", "Layer"],
  "timestamp": "2026-03-21T14:31:02Z",
  "checksum": "..."
}
DISPLAY: "Select object... [Through/Erase/Layer]"

EVENT 3 (optionSelected):
{
  "type": "optionSelected",
  "commandName": "OFFSET",
  "selectedOption": "Through",
  "timestamp": "2026-03-21T14:31:05Z",
  "checksum": "..."
}
DISPLAY: "Through" flashes briefly

EVENT 4 (commandCompleted):
{
  "type": "commandCompleted",
  "commandName": "OFFSET",
  "timestamp": "2026-03-21T14:31:15Z",
  "checksum": "..."
}
DISPLAY: Returns to "Ready"
```

---

## Testing

### Manual Event Injection

Send test events from command line:

```bash
# Test port 19848 with simple event
echo '{"type":"commandStarted","commandName":"TEST","timestamp":"2026-03-21T14:30:00Z","checksum":"abc123"}' | nc localhost 19848

# Test Unix socket
echo '{"type":"commandStarted","commandName":"TEST","timestamp":"2026-03-21T14:30:00Z","checksum":"abc123"}' | nc -U /tmp/tutorcast_autocad.sock
```

### Plugin Development Testing

```swift
// Simulate sending events (from test code)
let testEvent = """
{"type":"commandStarted","commandName":"LINE","timestamp":"2026-03-21T14:30:00Z","checksum":"a3f5b9e2..."}
"""

// Send via TCP
guard let host = NWEndpoint.Host("127.0.0.1"),
      let port = NWEndpoint.Port(rawValue: 19848) else { return }
let connection = nwConnection(to: .tcp(host: host, port: port))
// Send testEvent...
```

---

## Limits & Constraints

| Constraint | Limit | Reason |
|-----------|-------|--------|
| Event size | 512 bytes | Network efficiency |
| Command name | 64 chars | Display space |
| Subcommand text | 128 chars | Display space |
| Active options | 10 max | UI clarity |
| Option length | 64 chars | Display space |
| Events/second | 100 max | Rate limiting |
| Connection timeout | 30 seconds | Idle detection |
| Checksum algorithm | SHA-256 | Security |

---

## Security Considerations

1. **Checksum Validation:** All events verified with SHA-256
2. **Input Sanitization:** Control characters removed
3. **Length Limits:** Commands truncated to prevent buffer overflow
4. **Local-Only:** Unix socket and 127.0.0.1 only (for native)
5. **One-Way:** Events flow plugin → TutorCast only

---

## Integration Checklist

- [ ] Plugin sends valid JSON format
- [ ] All events include timestamp and checksum
- [ ] Newline-delimited format correct
- [ ] Checksums computed with SHA-256
- [ ] Command names correctly formatted
- [ ] Subcommand text trimmed and sanitized
- [ ] Options array not exceeding 10 items
- [ ] Event rate under 100/second
- [ ] TCP/Unix connection established
- [ ] Error responses handled

---

**Ready to integrate? See [PLUGIN_CONNECTION_GUIDE.md](PLUGIN_CONNECTION_GUIDE.md) for deployment instructions.**
