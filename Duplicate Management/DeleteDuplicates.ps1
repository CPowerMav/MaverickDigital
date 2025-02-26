$sourcePath = "\PathToSource\"
$duplicateFilesPath = "\PathToOutputFile\DuplicateFiles.txt"

# Get all files in the specified directory and its subdirectories
$files = Get-ChildItem -Path $sourcePath -Recurse -File

# Group files by hash
$hashGroups = $files | Get-FileHash | Group-Object -Property Hash

# Iterate through hash groups and keep only one file in each group
foreach ($group in $hashGroups) {
    if ($group.Count -gt 1) {
        # Sort the files by LastWriteTime in descending order, keeping the newest
        $filesToDelete = $group.Group | Sort-Object LastWriteTime -Descending | Select-Object -Skip 1

        # Delete the duplicate files
        foreach ($fileToDelete in $filesToDelete) {
            Remove-Item -Path $fileToDelete.FullName -Force
            Write-Host "Deleted duplicate file: $($fileToDelete.FullName)"
        }
    }
}

# Output the list of duplicate files to a text file with full paths
$files | Group-Object -Property Hash | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Group | Select-Object @{Name='FullName'; Expression={$_.FullName}} } | Out-File -FilePath $duplicateFilesPath
