# Prompt the user for the directory path
$directoryPath = Read-Host "Enter the directory path"

$files = Get-ChildItem -Recurse $directoryPath
$totalFiles = $files.Count
$processedFiles = 0

$files | ForEach-Object {
    $fileInfo = $_

    # Remove the root path from FullName
    $relativePath = $fileInfo.FullName.Substring($directoryPath.Length)

    $sizeInMB = [Math]::Round($fileInfo.Length / 1MB, 2)

    [PSCustomObject]@{
        FullName      = $relativePath
        SizeInMB      = $sizeInMB
        CreationTime  = $fileInfo.CreationTime
    }

    $processedFiles++
    $percentComplete = ($processedFiles / $totalFiles) * 100

    Write-Progress -Activity "Processing Files" -Status "Progress" -PercentComplete $percentComplete
} | Sort-Object FullName | Export-Csv -Force -NoTypeInformation -Path ".\fileList.csv"
