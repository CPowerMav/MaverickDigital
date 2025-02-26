# Prompt the user for the directory path
$directoryPath = Read-Host "Enter the directory path"

# Get only directories recursively
$directories = Get-ChildItem -Recurse -Directory $directoryPath
$totalDirectories = $directories.Count
$processedDirectories = 0

$directories | ForEach-Object {
    $directoryInfo = $_

    # Remove the root path from FullName
    $relativePath = $directoryInfo.FullName.Substring($directoryPath.Length)

    [PSCustomObject]@{
        FullName      = $relativePath
        CreationTime  = $directoryInfo.CreationTime
    }

    $processedDirectories++
    $percentComplete = ($processedDirectories / $totalDirectories) * 100

    Write-Progress -Activity "Processing Directories" -Status "Progress" -PercentComplete $percentComplete
} | Sort-Object FullName | Export-Csv -Force -NoTypeInformation -Path ".\directoryList.csv"
