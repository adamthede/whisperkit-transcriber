# Speaker Diarization Feature

## Overview

The WhisperKit Transcriber now supports **speaker diarization** - the ability to identify and label different speakers in audio recordings. This feature is especially valuable for:

- Interviews
- Meetings and conference calls
- Podcasts with multiple hosts
- Panel discussions
- Any multi-speaker audio content

## Features

### 1. Speaker Detection
- Automatically identifies different speakers in audio
- Assigns speaker IDs (e.g., SPEAKER_00, SPEAKER_01)
- Segments transcription by speaker

### 2. Speaker Labeling
- Assign custom names to speakers
- Replace generic IDs with meaningful names
- Labels persist across export formats

### 3. Export with Speaker Labels
- **Markdown**: Speaker names in bold before each segment
- **Plain Text**: Speaker names in brackets
- **JSON**: Full speaker segment data with timestamps
- Individual files include speaker metadata

## How to Use

### Enabling Diarization

1. Open the **Configuration** section in the app
2. Enable the **"Enable Speaker Diarization"** toggle
3. Configure the diarization server URL (default: `http://localhost:50061/diarize`)
4. Transcribe your audio files as usual

### Assigning Speaker Names

After transcription completes:

1. Select a transcription from the results list
2. Look for the **"Speaker Labels"** section
3. For each detected speaker:
   - Click **"Set Name"** or **"Edit"**
   - Enter a meaningful name (e.g., "John Smith", "Interviewer")
   - Click **"Save"**

### Viewing Speaker-Labeled Transcriptions

Transcriptions with speaker diarization show:
- Colored circles indicating each speaker
- Speaker names or IDs next to each segment
- Consistent color coding throughout the transcription

### Exporting

When exporting transcriptions with speaker labels:

**Markdown format:**
```markdown
**John Smith**: Hello, how are you today?

**Jane Doe**: I'm doing great, thanks for asking!
```

**Plain text format:**
```
[John Smith]: Hello, how are you today?

[Jane Doe]: I'm doing great, thanks for asking!
```

**JSON format:**
```json
{
  "has_speakers": true,
  "speaker_labels": {
    "SPEAKER_00": "John Smith",
    "SPEAKER_01": "Jane Doe"
  },
  "segments": [
    {
      "start_time": 0.0,
      "end_time": 5.2,
      "text": "Hello, how are you today?",
      "speaker": "SPEAKER_00",
      "speaker_name": "John Smith"
    }
  ]
}
```

## Setting Up the Diarization Server

### Option 1: Python Diarization Server

You can set up a simple diarization server using Python and pyannote.audio:

```bash
# Install dependencies
pip install flask pyannote.audio torch torchaudio

# Create server script (diarization_server.py)
# See example implementation below
```

Example server implementation:

```python
from flask import Flask, request, jsonify
from pyannote.audio import Pipeline
import torch

app = Flask(__name__)

# Load diarization pipeline
# Note: Requires Hugging Face token for pyannote models
pipeline = Pipeline.from_pretrained("pyannote/speaker-diarization")

@app.route('/diarize', methods=['POST'])
def diarize():
    if 'audio' not in request.files:
        return jsonify({"error": "No audio file provided"}), 400

    audio_file = request.files['audio']

    # Save temporarily
    temp_path = "/tmp/audio.wav"
    audio_file.save(temp_path)

    # Run diarization
    diarization = pipeline(temp_path)

    # Convert to segments
    segments = []
    for turn, _, speaker in diarization.itertracks(yield_label=True):
        segments.append({
            "start": turn.start,
            "end": turn.end,
            "speaker": speaker
        })

    return jsonify({"segments": segments})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=50061)
```

Run the server:
```bash
python diarization_server.py
```

### Option 2: WhisperKit CLI Native Diarization

If your version of WhisperKit CLI supports diarization natively (with `--diarize` flag), the app will automatically use it instead of requiring a separate server.

Check if your WhisperKit CLI supports diarization:
```bash
whisperkit-cli transcribe --help | grep -i diar
```

## Technical Details

### Architecture

1. **DiarizationManager**: Handles diarization logic
   - Checks for WhisperKit CLI native support
   - Falls back to server-based diarization
   - Merges speaker segments with transcription

2. **TranscriptionSegment**: Model for text segments with speaker info
   - Start/end timestamps
   - Text content
   - Speaker ID and optional name

3. **TranscriptionResult**: Extended with speaker support
   - List of segments
   - Speaker labels dictionary
   - Helper methods for speaker queries

### Segment Merging

The diarization process:

1. Transcription is parsed into segments (sentences)
2. Diarization identifies speaker time ranges
3. Segments are merged based on time overlap
4. Each transcription segment is assigned a speaker ID

### Error Handling

If diarization fails:
- Transcription continues without speaker labels
- Warning is logged to console
- User sees transcription without speaker segmentation

## Troubleshooting

### "Diarization failed" error

**Possible causes:**
- Diarization server not running
- Incorrect server URL
- Server connection timeout
- Audio file format not supported

**Solutions:**
1. Verify server is running: `curl http://localhost:50061/diarize`
2. Check server URL in Configuration
3. Review server logs for errors
4. Ensure audio file is in supported format

### No speakers detected

**Possible causes:**
- Single-speaker audio
- Low audio quality
- Background noise

**Solutions:**
- Verify audio has multiple speakers
- Try with higher-quality audio
- Check diarization server configuration

### Speaker segments don't align with transcription

**Possible causes:**
- Timing estimation issues
- Diarization boundary detection errors

**Solutions:**
- Use audio with clear speaker transitions
- Consider adjusting diarization server sensitivity
- Review and manually correct speaker labels if needed

## Performance Considerations

- **Processing time**: Diarization adds 20-50% to transcription time
- **Accuracy**: Depends on audio quality and speaker distinctiveness
- **Server load**: Diarization is CPU/GPU intensive
- **Network latency**: Server-based approach requires network calls

## Privacy & Security

- Audio files are sent to the diarization server
- For sensitive content, run server locally
- Speaker labels are stored only in app memory and exports
- No speaker data is transmitted outside your network

## Future Enhancements

Planned improvements:
- [ ] Visual speaker timeline
- [ ] Speaker statistics (speaking time, word count)
- [ ] Filter/search by speaker
- [ ] Export speaker-specific transcriptions
- [ ] Automatic speaker naming (voice characteristics)
- [ ] Support for more diarization backends

## References

- [pyannote.audio](https://github.com/pyannote/pyannote-audio) - Speaker diarization toolkit
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - On-device speech recognition
- [Speaker Diarization](https://en.wikipedia.org/wiki/Speaker_diarisation) - Background information

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review server logs for detailed error messages
3. Open an issue on GitHub with:
   - Error messages
   - Audio file characteristics
   - Server configuration
   - App logs

---

**Note**: Speaker diarization is an experimental feature. Accuracy may vary based on audio quality, number of speakers, and acoustic conditions.
