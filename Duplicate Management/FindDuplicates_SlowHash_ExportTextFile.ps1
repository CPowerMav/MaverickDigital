$directory = "\PathToSource\"
$outputFile = "\PathToOutputFile\DuplicateFiles.txt"

# Create a hashtable to store file hashes and their paths
$fileHashes = @{}

# Iterate through files in the directory and its subdirectories
Get-ChildItem $directory -File -Recurse | ForEach-Object {
    $hash = Get-FileHash $_.FullName -Algorithm MD5 | Select-Object -ExpandProperty Hash

    # Check if the hash is already in the hashtable
    if ($fileHashes.ContainsKey($hash)) {
        # If a file with the same hash is found, append the current file to the duplicate list
        $fileHashes[$hash] += @($_.FullName)
    } else {
        # If the hash is not in the hashtable, add it with the current file path
        $fileHashes[$hash] = @($_.FullName)
    }
}

# Filter out hash entries with only one file (not duplicates)
$duplicates = $fileHashes.Values | Where-Object { $_.Count -gt 1 }

# Output duplicate files to the specified file
$duplicates | ForEach-Object { $_ | Out-File -Append -FilePath $outputFile }