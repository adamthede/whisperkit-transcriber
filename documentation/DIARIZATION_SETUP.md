# Audio Transcription Diarization Setup Guide

This guide provides complete instructions for enabling speaker diarization (speaker identification) with your local WhisperKit transcription setup.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Configuration](#configuration)
- [Usage](#usage)
- [Output Format](#output-format)
- [Troubleshooting](#troubleshooting)
- [Performance Notes](#performance-notes)
- [Alternative Setups](#alternative-setups)

## Prerequisites

### Required Software
- **Python 3.8+** (`python3 --version` to check)
- **pip** package manager
- **HuggingFace account** with access token

### Hardware Requirements
- **RAM**: 8GB minimum, 16GB recommended
- **Storage**: ~2GB for diarization models (downloaded on first use)
- **GPU**: Optional but recommended for faster processing

## Quick Start

1. **Get HuggingFace Token**
   ```bash
   # Visit https://huggingface.co/settings/tokens
   # Create token with "Read" permissions
   ```

2. **Run Automated Setup**
   ```bash
   cd "/Volumes/Extreme SSD/Audio Journal/2025 09-21 03-30-00 AUDIO JOURNAL - Early Morning with AT (Tascam DR-05)"
   ./setup_diarization.sh
   ```

3. **Start Diarization Server**
   ```bash
   export HF_TOKEN="your_token_here"
   source diarization_env/bin/activate
   python3 diarization_server.py
   ```

4. **Run Transcription with Diarization**
   ```bash
   # In a new terminal
   export ENABLE_DIARIZATION=1
   export DIARIZATION_SERVER_URL="http://localhost:50061/diarize"
   ./transcribe_here.sh
   ```

## Detailed Setup

### Step 1: HuggingFace Token Setup

1. Visit [HuggingFace Tokens](https://huggingface.co/settings/tokens)
2. Click "New token"
3. Give it a name (e.g., "Audio Diarization")
4. Set role to "Read"
5. Copy the generated token

### Step 2: Environment Setup

The automated setup script (`setup_diarization.sh`) handles:
- Python version verification
- Virtual environment creation
- Dependency installation (torch, pyannote.audio, flask)
- Pipeline testing

Run it with:
```bash
./setup_diarization.sh
```

### Step 3: Server Configuration

The diarization server (`diarization_server.py`) provides:
- REST API endpoint at `/diarize`
- Health check at `/health`
- Automatic cleanup of temporary files

### Step 4: Integration with Transcription

Your updated `transcribe_here.sh` script now supports:
- Optional diarization processing
- Speaker segmentation output
- Progress indicators for diarization steps

## Configuration

### Environment Variables

Set these before running transcription:

```bash
# Required for diarization server
export HF_TOKEN="hf_your_actual_token_here"

# Optional transcription script settings
export ENABLE_DIARIZATION=1
export DIARIZATION_SERVER_URL="http://localhost:50061/diarize"
```

### Server Configuration

The diarization server runs on `localhost:50061` by default. You can modify:
- Port number in `diarization_server.py`
- Host binding (currently localhost only)

## Usage

### Starting the Diarization Server

```bash
# Terminal 1: Start diarization server
cd "/Volumes/Extreme SSD/Audio Journal/2025 09-21 03-30-00 AUDIO JOURNAL - Early Morning with AT (Tascam DR-05)"
source diarization_env/bin/activate
export HF_TOKEN="your_token_here"
python3 diarization_server.py
```

### Running Transcription with Diarization

```bash
# Terminal 2: Run transcription
cd "/Volumes/Extreme SSD/Audio Journal/2025 09-21 03-30-00 AUDIO JOURNAL - Early Morning with AT (Tascam DR-05)"
export ENABLE_DIARIZATION=1
export DIARIZATION_SERVER_URL="http://localhost:50061/diarize"
./transcribe_here.sh
```

### Processing Status

You'll see progress indicators like:
```
[1/3] Processing: audio_file_01.wav
  ✓ Completed: audio_file_01.wav
  → Performing speaker diarization...
  ✓ Diarization completed
```

## Output Format

### Directory Structure
```
out/
├── md/                    # Markdown files with metadata
├── txt/                   # Plain text transcriptions
├── json/                  # Structured transcription data
├── srt/                   # Subtitle files
└── diarization/           # Speaker diarization results
    ├── file1.json
    ├── file2.json
    └── ...
```

### Diarization JSON Format
```json
{
  "diarization": [
    {
      "start": 0.0,
      "end": 3.2,
      "speaker": "SPEAKER_00"
    },
    {
      "start": 3.2,
      "end": 7.8,
      "speaker": "SPEAKER_01"
    },
    {
      "start": 7.8,
      "end": 12.1,
      "speaker": "SPEAKER_00"
    }
  ],
  "speakers": 2
}
```

### Combining Transcription + Diarization

To combine transcription with speaker labels, you can process the JSON outputs:

```python
import json

# Load transcription and diarization
with open('out/json/file.json') as f:
    transcription = json.load(f)

with open('out/diarization/file.json') as f:
    diarization = json.load(f)

# Combine segments with speakers
for segment in transcription['segments']:
    start_time = segment['start']
    end_time = segment['end']

    # Find which speaker was talking during this segment
    speaker = "UNKNOWN"
    for speaker_segment in diarization['diarization']:
        if (speaker_segment['start'] <= start_time < speaker_segment['end'] or
            speaker_segment['start'] < end_time <= speaker_segment['end']):
            speaker = speaker_segment['speaker']
            break

    print(f"[{speaker}] {segment['text']}")
```

## Troubleshooting

### Server Won't Start

**Check port availability:**
```bash
lsof -i :50061
pkill -f diarization_server.py
```

**Verify Python environment:**
```bash
source diarization_env/bin/activate
python3 --version
pip list | grep pyannote
```

### Authentication Errors

**Test HuggingFace token:**
```bash
export HF_TOKEN="your_token_here"
python3 -c "from huggingface_hub import HfApi; api = HfApi(); print(api.whoami())"
```

**Check token permissions:**
- Token must have "Read" permissions
- Account must be verified (if required by model)

### Memory Issues

**Reduce processing load:**
- Process shorter audio files
- Close other memory-intensive applications
- Use CPU-only mode (modify server script)

**Monitor resources:**
```bash
# Check memory usage
top -l 1 | grep Python

# Check GPU usage (if available)
nvidia-smi
```

### Pipeline Loading Errors

**Clear cache and retry:**
```bash
rm -rf ~/.cache/pyannote*
source diarization_env/bin/activate
python3 diarization_server.py
```

### Integration Issues

**Verify server is running:**
```bash
curl http://localhost:50061/health
```

**Check transcription script variables:**
```bash
echo $ENABLE_DIARIZATION
echo $DIARIZATION_SERVER_URL
```

## Performance Notes

### Processing Times
- **First run**: 2-5 minutes (model download)
- **Subsequent runs**: 10-30 seconds per minute of audio
- **Hardware acceleration**: 2-3x faster with GPU

### Optimization Tips
- Use shorter audio files for testing
- Process in batches if memory allows
- Consider CPU-only for development/testing

### Resource Usage
- **CPU**: High during processing
- **RAM**: 4-8GB per concurrent file
- **GPU**: ~2GB VRAM if available
- **Storage**: 2GB model cache + output files

## Alternative Setups

### Manual Installation

If automated setup fails:

```bash
# Create and activate virtual environment
python3 -m venv diarization_env
source diarization_env/bin/activate

# Install dependencies
pip install torch pyannote.audio flask

# Set token and test
export HF_TOKEN="your_token_here"
python3 -c "from pyannote.audio import Pipeline; p = Pipeline.from_pretrained('pyannote/speaker-diarization-3.1', use_auth_token='$HF_TOKEN'); print('Success')"
```

### Different Diarization Models

**NVIDIA NeMo** (alternative to pyannote):
```bash
pip install nemo_toolkit[asr]
# Requires different server implementation
```

**speechbrain** (lighter weight):
```bash
pip install speechbrain
# Good for real-time processing
```

### Docker Setup

For containerized deployment:
```dockerfile
FROM python:3.9-slim

RUN pip install torch pyannote.audio flask
COPY diarization_server.py /app/
WORKDIR /app

EXPOSE 50061
CMD ["python3", "diarization_server.py"]
```

## Files Created

This setup creates several files in your transcription directory:

- `diarization_server.py` - Main diarization server
- `setup_diarization.sh` - Automated setup script
- `requirements-diarization.txt` - Python dependencies
- `DIARIZATION_SETUP.md` - This documentation

## Support

### Common Issues
1. **Token authentication** - Verify HF_TOKEN is set correctly
2. **Memory errors** - Process smaller files or add more RAM
3. **Port conflicts** - Change port in server script
4. **Model download** - Ensure stable internet connection

### Next Steps
- Test with short audio files first
- Experiment with different models
- Integrate diarization output into your workflow
- Consider batch processing for multiple files

---

*Last updated: $(date)*
*For issues or questions, check the troubleshooting section above.*
