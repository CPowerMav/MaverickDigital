# Prompt the user for the input folder containing the .mov and .wav files
$inputFolder = Read-Host "Enter the path to the folder containing .mov and .wav files"

# Verify if the folder exists
if (-not (Test-Path $inputFolder)) {
    Write-Error "The specified folder does not exist. Please check the path and try again."
    exit 1
}

# Get a list of all .mov files in the folder
$movFiles = Get-ChildItem -Path $inputFolder -Filter *.mov

if ($movFiles.Count -eq 0) {
    Write-Error "No .mov files found in the specified folder."
    exit 1
}

# Loop through each .mov file in the folder
foreach ($movFile in $movFiles) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($movFile.Name)
    $wavFile = Join-Path -Path $inputFolder -ChildPath ($baseName + ".wav")
    
    # Check if the corresponding .wav file exists
    if (-not (Test-Path $wavFile)) {
        Write-Warning "No matching .wav file found for: $($movFile.Name). Skipping..."
        continue
    }
    
    # Define the output file path with proper string concatenation
    $outputFile = Join-Path -Path $inputFolder -ChildPath ($baseName + "_restriped.mov")
    
    # Extract the original audio codec format from the .mov file
    $ffprobeCommand = "ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 `"$($movFile.FullName)`""
    $originalAudioCodec = & cmd /c $ffprobeCommand
    
    if (-not $originalAudioCodec) {
        Write-Warning "Failed to determine the audio codec for: $($movFile.Name). Skipping..."
        continue
    }
    
    # Construct the ffmpeg command to replace the audio
    $ffmpegCommand = "ffmpeg -i `"$($movFile.FullName)`" -i `"$wavFile`" -c:v copy -c:a $originalAudioCodec -map 0:v:0 -map 1:a:0 `"$outputFile`""
    
    # Execute the ffmpeg command
    Write-Host "Processing $($movFile.Name)..."
    & cmd /c $ffmpegCommand
    
    # Check if the output file was created successfully
    if (Test-Path $outputFile) {
        Write-Host "Audio replacement completed for: $($movFile.Name). Output saved to: $outputFile"
    } else {
        Write-Warning "Failed to replace audio for: $($movFile.Name)."
    }
}

Write-Host "Batch processing completed."