# Script to extract audio from all video files in a directory and save them as WAV files with a 48kHz sample rate
param(
    [string]$InputDirectory # The directory containing the video files
)

# Prompt the user for the input directory if not provided
if (-not $InputDirectory) {
    $InputDirectory = Read-Host "Enter the full path to the directory containing video files (supports UNC paths)"
}

# Validate the input directory
if (-not (Test-Path $InputDirectory -PathType Container)) {
    Write-Host "Invalid directory: $InputDirectory" -ForegroundColor Red
    exit 1
}

# Ensure UNC paths are supported by checking access permissions
try {
    Get-ChildItem $InputDirectory -ErrorAction Stop | Out-Null
} catch {
    Write-Host "Cannot access the directory: $InputDirectory. Ensure it is a valid path and you have access permissions." -ForegroundColor Red
    exit 1
}

# Create the output directory
$outputDirectory = Join-Path $InputDirectory "output"
if (-not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

# Check if FFmpeg is installed
if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue)) {
    Write-Host "FFmpeg is not installed or not in the system PATH. Please install it and try again." -ForegroundColor Red
    exit 1
}

# Process all .mov files in the input directory
$videoFiles = Get-ChildItem -Path $InputDirectory -Filter *.mov -File
if (-not $videoFiles) {
    Write-Host "No video files found in the directory: $InputDirectory" -ForegroundColor Yellow
    exit 1
}

foreach ($file in $videoFiles) {
    # Generate the output file path with the same name as the input file but with .wav extension
    $outputFile = Join-Path $outputDirectory ([System.IO.Path]::GetFileNameWithoutExtension($file.Name) + ".wav")
    
    Write-Host "Processing $($file.FullName)..."
    try {
        # Use FFmpeg to extract the audio with 48kHz sample rate
        & ffmpeg -i $file.FullName -vn -acodec pcm_s16le -ar 48000 -ac 2 $outputFile -y
        Write-Host "Extracted: $outputFile" -ForegroundColor Green
    } catch {
        Write-Host "Failed to process $($file.FullName): $_" -ForegroundColor Red
    }
}

Write-Host "Processing complete. Extracted files are in: $outputDirectory" -ForegroundColor Green
