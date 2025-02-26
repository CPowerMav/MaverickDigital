<#
This script processes all video files in a user-specified directory,
removes their audio tracks, and saves the modified files to an "output"
folder within the same directory. Supported formats include .mp4, .mov,
.mkv, .avi, .flv, and .wmv. The output files retain their original
extensions but have "_no_audio" appended to their filenames. The script
supports UNC paths, validates the input directory, and ensures FFmpeg is
installed before running.
#>

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

# Process all supported video files in the input directory
$supportedExtensions = "*.mp4", "*.mov", "*.mkv", "*.avi", "*.flv", "*.wmv"
$videoFiles = Get-ChildItem -Path $InputDirectory -File -Include $supportedExtensions
if (-not $videoFiles) {
    Write-Host "No video files found in the directory: $InputDirectory" -ForegroundColor Yellow
    exit 1
}

foreach ($file in $videoFiles) {
    # Generate the output file path with "_no_audio" appended to the filename
    $outputFile = Join-Path $outputDirectory ($file.BaseName + "_no_audio" + $file.Extension)
    
    Write-Host "Processing $($file.FullName)..."
    try {
        # Use FFmpeg to strip audio while keeping video intact
        & ffmpeg -i $file.FullName -c copy -an $outputFile -y
        Write-Host "Processed: $outputFile" -ForegroundColor Green
    } catch {
        Write-Host "Failed to process $($file.FullName): $_" -ForegroundColor Red
    }
}

Write-Host "Processing complete. Files with audio removed are in: $outputDirectory" -ForegroundColor Green