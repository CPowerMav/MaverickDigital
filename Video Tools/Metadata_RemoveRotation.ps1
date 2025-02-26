# Prompt the user for the directory path
$directory = Read-Host "Enter the directory path"

# Get all MP4 files in the directory
$files = Get-ChildItem -Path $directory -Filter "*.mp4"

# Initialize the progress bar
$totalFiles = $files.Count
$currentFile = 0

foreach ($file in $files) {
    $currentFile++

    # Update the progress bar
    $percentComplete = ($currentFile / $totalFiles) * 100
    Write-Progress -PercentComplete $percentComplete -Status "Fixing Rotation" -Activity "Processing: $($file.Name)" -CurrentOperation "$currentFile of $totalFiles"

    # Get rotation metadata using exiftool with LargeFileSupport
    $rotation = & exiftool -s -s -s -api LargeFileSupport=1 -Rotation "$($file.FullName)"

    if ($rotation -eq "90") {
        Write-Host "Fixing rotation for: $($file.Name)"
        & exiftool -api LargeFileSupport=1 -rotation=0 -overwrite_original "$($file.FullName)"
    } else {
        Write-Host "Skipping: $($file.Name) (Rotation: $rotation)"
    }
}

# Complete the progress bar once all files are processed
Write-Progress -PercentComplete 100 -Status "Completed" -Activity "All files processed" -CurrentOperation "Finished"
