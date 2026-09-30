# SayTTS

OpenAI Speech API compatible Text-to-Speech server for macOS using the built-in `say` command.

## Requirements

- macOS 14.0+
- Xcode Command Line Tools (for `swift` and `afconvert`)
- ffmpeg (for MP3 and Opus format support)

Install ffmpeg via Homebrew:
```bash
brew install ffmpeg
```

## Building

```bash
swift build
```

## Installing as a service

To install TTSServer as a launchd service that starts automatically:

```bash
make service
```

This will:
1. Build the release binary
2. Install it to `~/.bin/TTSServer`
3. Create a launchd plist at `~/Library/LaunchAgents/HatsumeAI.TTSServer.plist`

### Service configuration

The service can be configured with variables when installing:

```bash
# Custom port
make service HTTP_PORT=3000

# Custom host and port
make service HTTP_HOST=0.0.0.0 HTTP_PORT=9000

# Custom ffmpeg path
make service FFMPEG_PATH=/usr/local/bin/ffmpeg

# All variables
make service HTTP_HOST=0.0.0.0 HTTP_PORT=3000 FFMPEG_PATH=/usr/local/bin/ffmpeg
```

Manage the service with:

```bash
# Start the service
make start

# Stop the service
make stop

# Restart the service
make restart

# Or manually with launchctl
launchctl load ~/Library/LaunchAgents/HatsumeAI.TTSServer.plist
launchctl unload ~/Library/LaunchAgents/HatsumeAI.TTSServer.plist

# Check service status
launchctl list | grep TTSServer
```

## Running

```bash
swift run
```

The server defaults to `http://127.0.0.1:9000`

### Configuration

The server can be configured via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `HTTP_HOST` | `127.0.0.1` | Host address to bind to. Use `0.0.0.0` to accept connections from the local network |
| `HTTP_PORT` | `9000` | Port number to listen on |
| `HTTP_TOKEN` | *(empty)* | Bearer token required on every request. Empty means no authentication |
| `FFMPEG_PATH` | *(auto-detected)* | Path to ffmpeg executable. Required for MP3 and Opus |

Example:

```bash
HTTP_HOST=0.0.0.0 HTTP_PORT=3000 FFMPEG_PATH=/usr/local/bin/ffmpeg swift run
```

With a token, every request must carry `Authorization: Bearer <token>`:

```bash
HTTP_TOKEN=s3cret swift run

curl -X POST http://127.0.0.1:9000/v1/audio/speech \
  -H "Authorization: Bearer s3cret" \
  -H "Content-Type: application/json" \
  -d '{"input": "Hello, world!", "model": "tts-1", "response_format": "aiff"}' \
  --output speech.aiff
```

## Using the library

The package ships two products:

| Product | Kind | Use |
|---------|------|-----|
| `TTSServerKit` | library | Embed the server in another app and drive it from the UI |
| `TTSServer` | executable | Run it standalone, e.g. under launchd |

`TTSServerService` starts and stops an HTTP listener on demand:

```swift
import TTSServerKit

let service = TTSServerService(
    configuration: .init(host: "127.0.0.1", port: 9000, token: nil)
)

try await service.start()   // returns once the socket is bound, throws if the port is taken
await service.stop()        // drains in-flight requests, then closes the listener
```

`start()` resolves only after the address is actually bound, and throws a
`TTSServerError.startupFailed` with a readable reason (such as "port already in
use") if it cannot be. `state` reports the current lifecycle status.

## Using Siri voices

It's possible to use high quality siri voices using say command as default voice.
You need to go to System Settings - Assessibility - Spoken content, then select default language and voice.

Siri voices cannot be referred directly as voice argument but it works as default one.

## API Endpoints

All endpoints are OpenAI Speech API compatible. When `HTTP_TOKEN` is set, every
request must include `Authorization: Bearer <token>` or it is answered with
`401 Unauthorized`.

### POST /v1/audio/speech

Generate audio from text.

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `input` | string | Yes | Text to convert to speech (max 4096 characters) |
| `model` | string | Yes | Must be `"tts-1"` (validated, no effect on output) |
| `voice` | string | No | Voice name (e.g., "Alex", "Samantha"). Defaults to system voice. |
| `response_format` | string | No | Audio format. Default: `"mp3"` |
| `instructions` | string | No | Accepted for compatibility, ignored |

**Response:** Audio file with appropriate `Content-Type` header.

### POST /v1/audio/transcriptions

Transcribe an audio file using on-device Apple Speech recognition.

**Request Body:** `multipart/form-data`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `file` | file | Yes | The audio file to transcribe |
| `model` | string | Yes | Locale identifier for the recognizer, e.g. `"ru-RU"`, `"en-US"` |
| `response_format` | string | No | `"json"` (default) or `"text"` |
| `prompt` | string | No | Accepted for compatibility, ignored |
| `temperature` | number | No | Accepted for compatibility, ignored |

**Response:** `{"text": "..."}` by default, or plain text with `response_format=text`.

```bash
curl -X POST http://127.0.0.1:9000/v1/audio/transcriptions \
  -F "file=@Media/russian.wav" \
  -F "model=ru-RU"
```

### POST /v1/audio/translations

Same behaviour as `/v1/audio/transcriptions`. Apple Speech transcribes in the
locale's own script, so this endpoint currently returns the transcription rather
than an English translation.

## Supported Formats

| Format | Supported | Description |
|--------|-----------|-------------|
| **aac** | Yes | Digital audio compression, preferred by YouTube, Android, iOS |
| **flac** | Yes | Lossless audio compression for archiving |
| **wav** | Yes | Uncompressed WAV at 24kHz mono, 16-bit PCM |
| **pcm** | Yes | Raw 24kHz mono, 16-bit signed little-endian samples (no header) |
| **aiff** | Yes | Default output from `say` command |
| **mp3** | Yes | MP3 encoding (requires ffmpeg) |
| **opus** | Yes | Opus encoding (requires ffmpeg) |

> Note: MP3 and Opus formats require ffmpeg to be installed on your system.

## Usage Examples

### Generate AIFF audio (default voice)

```bash
curl -X POST http://127.0.0.1:8080/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{
    "input": "Hello, world!",
    "model": "tts-1",
    "response_format": "aiff"
  }' \
  --output speech.aiff
```

### Use a specific voice

```bash
# List available voices: say -v '?'
curl -X POST http://127.0.0.1:8080/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{
    "input": "The quick brown fox jumps over the lazy dog.",
    "model": "tts-1",
    "voice": "Samantha",
    "response_format": "aac"
  }' \
  --output speech.aac
```

### Generate WAV format (24kHz uncompressed)

```bash
curl -X POST http://127.0.0.1:8080/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{
    "input": "This is uncompressed audio.",
    "model": "tts-1",
    "response_format": "wav"
  }' \
  --output speech.wav
```

### Generate raw PCM (24kHz, 16-bit signed little-endian)

```bash
curl -X POST http://127.0.0.1:8080/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{
    "input": "Raw PCM data without headers.",
    "model": "tts-1",
    "response_format": "pcm"
  }' \
  --output speech.pcm
```

### Generate FLAC (lossless)

```bash
curl -X POST http://127.0.0.1:8080/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{
    "input": "Lossless compressed audio.",
    "model": "tts-1",
    "response_format": "flac"
  }' \
  --output speech.flac
```

### Generate MP3 (requires ffmpeg)

```bash
curl -X POST http://127.0.0.1:8080/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{
    "input": "MP3 compressed audio.",
    "model": "tts-1",
    "response_format": "mp3"
  }' \
  --output speech.mp3
```

### Generate Opus (requires ffmpeg)

```bash
curl -X POST http://127.0.0.1:8080/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{
    "input": "Opus compressed audio.",
    "model": "tts-1",
    "response_format": "opus"
  }' \
  --output speech.opus
```

## Testing

Run the test suite:

```bash
swift test
```

## Error Responses

| Error | Description |
|-------|-------------|
| `Invalid model` | Model must be `"tts-1"` |
| `Invalid input` | Input text is empty or exceeds 4096 characters |
| `Format not supported` | Requested format is not available |
| `Say command failed` | Underlying `say` command error |
| `Audio conversion failed` | `afconvert` or `ffmpeg` conversion error |

## License

MIT
