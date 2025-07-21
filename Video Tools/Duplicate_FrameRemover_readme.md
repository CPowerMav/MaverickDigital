# Duplicate Frame Remover

A simple FFmpeg-based tool to automatically detect and remove duplicate frames from videos while preserving the original frame rate and encoding to high-quality ProRes 422.

## What It Does

This tool analyzes your video files and removes consecutive duplicate frames that can occur from:
- Security camera recordings with static scenes
- Screen recordings with minimal changes
- Corrupted or improperly encoded videos
- Time-lapse footage with repeated frames

The tool uses FFmpeg's `mpdecimate` filter to intelligently detect duplicate frames and removes them while maintaining smooth playback at the original frame rate.

## Features

- **Automatic duplicate detection** - Uses advanced algorithms to identify truly duplicate frames
- **Frame rate preservation** - Maintains original video frame rate
- **High-quality output** - Encodes to ProRes 422 for professional workflows
- **Cross-platform** - Works on Windows, macOS, and Linux
- **Batch processing ready** - Easy to integrate into automated workflows
- **Flexible naming** - Automatic output naming or custom filenames

## Requirements

- [FFmpeg](https://ffmpeg.org/download.html) installed and accessible from command line
- FFprobe (included with FFmpeg)

## Installation

1. Download the appropriate script for your platform:
   - `remove_duplicates.sh` (Linux/macOS)
   - `remove_duplicates.bat` (Windows)

2. Make the script executable (Linux/macOS only):
   ```bash
   chmod +x remove_duplicates.sh
   ```

## Usage

### Linux/macOS
```bash
# Basic usage - outputs to filename_no_duplicates.mov
./remove_duplicates.sh input_video.mp4

# Custom output filename
./remove_duplicates.sh input_video.mp4 output_video.mov

# Process multiple files
for file in *.mp4; do ./remove_duplicates.sh "$file"; done
```

### Windows
```batch
# Basic usage - outputs to filename_no_duplicates.mov
remove_duplicates.bat input_video.mp4

# Custom output filename
remove_duplicates.bat input_video.mp4 output_video.mov

# Process multiple files
for %f in (*.mp4) do remove_duplicates.bat "%f"
```

## How It Works

1. **Frame Analysis** - Uses `mpdecimate` filter with sensitivity settings (hi=200:lo=200:frac=1:max=0)
2. **Timestamp Correction** - Adjusts presentation timestamps with `setpts=N/FRAME_RATE/TB`
3. **Quality Encoding** - Outputs to ProRes 422 with uncompressed audio
4. **Frame Rate Matching** - Automatically detects and preserves original frame rate

## Output Specifications

- **Video Codec**: Apple ProRes 422 (profile 2)
- **Audio Codec**: PCM 16-bit uncompressed
- **Container**: QuickTime (.mov)
- **Quality**: Visually lossless compression
- **Compatibility**: Professional video editing software

## Example Results

Typical file size changes:
- **Input**: 100MB H.264 MP4
- **Output**: 300-800MB ProRes 422 MOV (depending on content)

Frame reduction varies by content:
- Static security footage: 50-90% frame reduction
- Dynamic content: 5-20% frame reduction
- Screen recordings: 30-70% frame reduction

## Customization

### Different ProRes Profiles
Modify the `-profile:v` parameter:
- `0` = ProRes 422 Proxy (smallest)
- `1` = ProRes 422 LT
- `2` = ProRes 422 (default)
- `3` = ProRes 422 HQ
- `4` = ProRes 4444
- `5` = ProRes 4444 XQ (largest)

### Sensitivity Adjustment
Modify the `mpdecimate` parameters for different sensitivity:
```bash
# More aggressive (removes more frames)
-vf "mpdecimate=hi=100:lo=100:frac=0.5:max=0,setpts=N/FRAME_RATE/TB"

# More conservative (removes fewer frames)  
-vf "mpdecimate=hi=400:lo=400:frac=1.5:max=0,setpts=N/FRAME_RATE/TB"
```

## Troubleshooting

**Error: "ffmpeg not found"**
- Install FFmpeg and ensure it's in your system PATH

**Large output files**
- This is expected with ProRes - use lower profile if size is a concern

**No frames removed**
- Your video may not have duplicate frames, or sensitivity needs adjustment

## License

This project is released under the MIT License. Feel free to modify and distribute.

## Contributing

Issues and pull requests welcome! Please test thoroughly before submitting changes.