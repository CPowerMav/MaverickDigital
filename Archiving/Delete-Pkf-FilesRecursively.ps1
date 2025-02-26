# Prompt the user to enter the UNC network path
$path = Read-Host "Enter the UNC network path"

# Check if the entered path is valid
if (!(Test-Path -Path $path)) {
    Write-Error "Invalid path: $path"
    exit 1
}

# Specify the file extensions to delete
$extensions = @("*.cfa", "*.pek", "*.pkf")

# Initialize a counter for deleted files
$deletedCount = 0

try {
    # Get files matching the extensions recursively and delete them
    foreach ($extension in $extensions) {
        Get-ChildItem -Path $path -Filter $extension -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                $deletedCount++
            } catch {
                Write-Warning "Failed to delete file: $($_.FullName)"
            }
        }
    }

    Write-Host "Deleted $deletedCount files successfully."
} catch {
    Write-Error "An error occurred: $_"
}