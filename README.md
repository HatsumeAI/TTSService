OpenAI Speech API compatible Text-to-Speech for macOS, served from the menu bar.

SayTTS runs an HTTP server built on the system `say` command and exposes the
OpenAI-compatible `/v1/audio/*` endpoints. It lives in the menu bar: left click
opens settings, right click shows the status and a quit action.

## Requirements

- macOS 15.0+ (the embedded Hummingbird server requires it)
- Xcode Command Line Tools (for `say` and `afconvert`)
- ffmpeg, for MP3 and Opus output

```bash
brew install ffmpeg
```

## Building

```bash
make build
```

or from Xcode, with the `SayTTS` scheme.

## Running

Start the server from the settings panel, or tick **Start serving when SayTTS
opens** to have it come up with the app. It listens on `http://127.0.0.1:9000` by
default; turn on **Serve on local network** to bind `0.0.0.0` instead.

Settings are locked while the server is starting, running or stopping, because
the listener holds the port until it stops.

### Authentication

With **Require authentication** enabled, every request must carry a matching
bearer token or it is answered with `401 Unauthorized`:

```bash
curl -X POST http://127.0.0.1:9000/v1/audio/speech \
  -H "Authorization: Bearer s3cret" \
  -H "Content-Type: application/json" \
  -d '{"input": "Hello, world!", "model": "tts-1", "response_format": "aiff"}' \
  --output speech.aiff
```

Tokens are compared in constant time.

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
curl -X POST http://127.0.0.1:9000/v1/audio/speech \
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
curl -X POST http://127.0.0.1:9000/v1/audio/speech \
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
curl -X POST http://127.0.0.1:9000/v1/audio/speech \
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
curl -X POST http://127.0.0.1:9000/v1/audio/speech \
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
curl -X POST http://127.0.0.1:9000/v1/audio/speech \
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
curl -X POST http://127.0.0.1:9000/v1/audio/speech \
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
curl -X POST http://127.0.0.1:9000/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{
    "input": "Opus compressed audio.",
    "model": "tts-1",
    "response_format": "opus"
  }' \
  --output speech.opus
```

## Testing

Run the test suite (28 tests across 4 suites):

```bash
make test
```

or `⌘U` in Xcode.

The tests cover server configuration, bearer-token middleware, multipart
parsing, error descriptions, audio formats, and request validation. They drive
the middleware directly rather than through `HummingbirdTesting`, which pulls in
`swift-nio-transport-services` — that package fails to link when Xcode builds it
as a dynamic product.

## Layout

| Path | Contents |
|------|----------|
| `SayTTS/AppDelegate.swift` | Status item, left/right click split, settings panel |
| `SayTTS/AppModel.swift` | Persisted settings, server lifecycle, validation |
| `SayTTS/SettingsView.swift` | The settings panel UI |
| `SayTTS/TTSServerKit/` | The embedded HTTP server (Hummingbird) |
| `SayTTSTests/` | Test suite |

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
