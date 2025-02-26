# Prompt the user for the CSV file path
$csvFilePath = Read-Host "Enter the CSV file path"

# Read the CSV file
$directoryList = Import-Csv $csvFilePath

# Prompt the user for the target root directory where the new structure will be created
$targetRootDirectory = Read-Host "Enter the target root directory path"

# Iterate through each row in the CSV and create the corresponding folder structure
foreach ($entry in $directoryList) {
    $fullPath = Join-Path -Path $targetRootDirectory -ChildPath $entry.FullName

    # Create the directory if it doesn't exist
    if (-not (Test-Path $fullPath -PathType Container)) {
        New-Item -ItemType Directory -Path $fullPath -Force
    }
}

Write-Host "Folder structure created successfully."
