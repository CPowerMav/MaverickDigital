###########################################################################################
################################# ScanMedia.ps1 ###########################################
###########################################################################################
#Requires -Version 3

<#

.SYNOPSIS
    A validation check on video files to make sure there are no errors with the file. The script is able to auto-repair some encoding issues with video files.
    The script will keep track of all scanned files that are not deleted so that it can be setup to re-scan the same directory but only newly added files will be scanned.
    Script use: Takes a PATH parameter to a folder for scanning media

.EXAMPLE
.\ScanMedia.ps1 -Path "C:\Media\Videos"
    Both recursively scans the folder C:\Media\Videos for errors

.\ScanMedia.ps1 -AutoRepair "C:\Media\Videos"
    To scan media and attempt to Auto Repair files use -AutoRepair

.\ScanMedia.ps1 -Rescan "C:\Media\Videos"
    To scan media and force a re-scan of all files use -Rescan

.\ScanMedia.ps1 -CRF 18 -Path "C:\Media\Videos" -AutoRepair
    To Change the CRF Value used for encodes, change the following

.\ScanMedia.ps1 -Path "C:\Media\Videos" -LimitCPU -AutoRepair -RemoveOriginal -RemoveRepaired
    Scans the path C:\Media\Videos with lower CPU usage and attempts to repair the files that are found to have an issue. 
    The script will delete repaired files that don't repair properly and it will delete the original files of successfully repaired files.

.NOTES
    Changelog:
        1.O - Initial Script creation
        1.1 - Separated the Error Log files as some could be very big
        1.2 - Incorporated an Auto-Repair function
        1.3 - Added additional logging to CSV file for easy sorting
        1.4 - Corrected issue with detecting old error logs
        1.5 - Added check to make sure ffmpeg exists and change calling behavior
        1.6 - Implemented Join-Path to allow script to be run on non-Windows machines
        1.7 - Enable file scanned history and added a -Rescan switch to force scanning
                all files.
        1.8 - Found an Error with Get-ChildItem and -path where it wouldn't scan top
                level folders with [] in the name. Using -LiteralPath now.
        1.9 - Fixed an issue with LiteralPath ignoring ignored extensions
        1.9.1 Changed how the auto-repair function worked to duplicate plex's optimized
                version settings to create an x264 file to better address file errors. It
                can now correct more issues but not everything. Added a CRF argument so
                users can now select the quality of the repaired video files.
                Enabled AutoDelete on repaired files only that have failed checks
        1.9.2 Corrected issue with not getting the file size on a video file for a PASSED
                video file. Modified the writing of the CSV into a function to remove commas
                from file names
        2.0 - Changed ScanPath to Path. Corrected double logging of repaired files. Bugfixes.
                Moved log directories into a Log folder for better organization
                Condensed the method of writing output
        2.1 - Correct issue with logging skipped files
        2.2 - Added the ability to Limit CPU usage to half the cores detected on the machine.
                Added the ability to remove original files and all files that are found with errors.
        2.3 - Corrected issue with testing a path of a file containing "[]" characters
        3.0 - Major Update: Massive re-write and new feature introduction. New Menu for easier user interaction. New scanning user interface. Updated output and moved more information to the log file.
                Added the following new parameters:
                    -ConfigFile
                    -IdleScan
                    -BypassMenu
                    -GPUEncoding
                    -Extension
                    -ContinuousScan
                Moved the parameter overview into the user interface help menu. Created new methods and options for automation including -ConfigFile, -IdleScan, -ContinuousScan
                New built in version checker which will scan the GitHub repo on startup of the user interface and check for a new version.
                New FFMPEG utility menu which will help the user download a copy of FFMPEG and place it in the correct directory.
                New Help menu to help guide users on the functionality of the script.
                New CPU idle function that will only scan when the machine's CPU is idle and not working on other processes
                A bunch of bugfixes
        3.1 - New Feature: -TrashEnabled This command will allow you to send files are found to have errors to a single directory for further analysis and some minor bugfixes
        3.2 - Added a check to make sure write access was available to the ffmpeg binary
        3.3 - Added arguments for FFMPEG to increase compatibility with larger file formats (Should fix Too many packets buffered for output stream error)
            - Changed file extension exclusion list to inclusion list, so now it will only target media files with the extensions provided in $include
            - Changed some wording surrounding the failed deletion prompt for better understanding
        3.4 - Fixed output when scans were started on very long file paths
            - Added more feedback to let the user know a scan was in progress
        3.5 - Correct issues with running inside of PowerShell ISE

                Note: It continue to use the command line parameters for calling syntax through 3rd party applications, please include the new parameter -BypassMenu to avoid user interaction from halting the script.
                Note: If resizing the PowerShell window during a scan, the text will adjust to the new screen size on an output change. So just wait and it will refresh and correct the output.
                Note: The new scanning output will only show the results of the last 30 items scanned. The log file must be used to view previous scan results. A log viewing tool is recommended when viewing the log files.

    You are able to take advantage of encoding with GPU Acceleration on linux and windows if you compile the ffmpeg binaries to support nvec.
    This has not been tested with this script and is not supported but it should still be possible.
    Please refer to this link to see if your GPU is supported: https://developer.nvidia.com/ffmpeg
    1: Compile FFMPEG using this cross compile script:
    https://github.com/rdp/ffmpeg-windows-build-helpers
    2: Verify that the new NVENC encoders are now included by using the following commands against the the compiled FFMPEG binaries:
    ffmpeg -encoders
    ffmpeg -decoders
    3: Find and replace the following term "libx264" with "h264_nvenc" in this script
    Encoding should now be utilizing the GPU instead of the CPU

    Thank you to all the users for their feedback on issues and feature requests
#>

[CmdletBinding()]
Param (
    [String]$Path,
    [String]$ConfigFile,
    [switch]$AutoRepair,
    [switch]$Rescan,
    [Int]$CRF = 21,
    [switch]$LimitCPU,
    [switch]$RemoveAll,
    [switch]$RemoveRepaired,
    [switch]$RemoveOriginal,
    [switch]$IAcceptResponsibility,
    [switch]$IdleScan,
    [switch]$BypassMenu,
    [switch]$GPUEncoding,
    [String]$Extension = "mp4",
    [switch]$ContinuousScan,
    [String]$TrashEnabled
)

# Included file types. Add more extensions that you want included with the media scan
$include = ".mp4", ".avi", ".mkv", ".m4v", ".ogg", ".mpeg", ".wmv", ".flv", ".mov", ".ogv", ".mpg", ".m4a", ".asf", ".ts", ".divx"

# Script Variables
[float]$ScriptVersion = 3.5
$fullName = ""
$fileName = ""
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
$scanHistory = Join-Path -path $scriptPath -childpath "ScanHistory.txt"
$Date = "$((Get-Date).ToString('yyyy-MM-dd'))"
$LogDir = Join-Path -path $scriptPath -childpath "log"
$LogPath = Join-Path -path $LogDir -childpath "log_$Date"
$ffmpegLog = Join-Path -path $LogPath -childpath "ffmpegerror.log"
$Logfile = Join-Path -path $LogPath -childpath "results.log"
$CSVfile = Join-Path -path $LogPath -childpath "results.csv"
$env:PATH = $env:PATH + ";."
$global:OrigLength = $null
$global:RepairLength = $null
$global:RepairedFile = $null
$global:OriginalFile = $null
$global:OriginalRemoved = $false
$global:CPULimt = 1
$global:VideoLibrary = "libx264"

# Convert all Supplied Parameters to Global variables for use in all functions
$global:Path = $Path
$global:ConfigFile = $ConfigFile
$global:AutoRepair = $AutoRepair
$global:Rescan = $Rescan
$global:CRF = $CRF
$global:LimitCPU = $LimitCPU
$global:RemoveAll = $RemoveAll
$global:RemoveRepaired = $RemoveRepaired
$global:RemoveOriginal = $RemoveOriginal
$global:IAcceptResponsibility = $IAcceptResponsibility
$global:IdleScan = $IdleScan
$global:GPUEncoding = $GPUEncoding
$global:RepairVFileExtension = $Extension
$global:ContinuousScan = $ContinuousScan
$global:TrashEnabled = $TrashEnabled

# Function to write lines to a log file
Function LogWrite {
    Param (
        [String]$LogString,
        [String]$Colour,
        [switch]$Log)
 
    If (!($log)) {
        If ($Colour) {
            Write-Host "$(Get-Date): $LogString" -ForegroundColor $Colour
        }
        Else {
            Write-Host "$(Get-Date): $LogString"
        } 
    }
    Add-content $LogFile -value "$(Get-Date): $LogString" -Force
}

Function Write-PauseMessage {
    param(
        [String]$message)
    # Check if running Powershell ISE
    if ($psISE) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show("$message")
    }
    else {
        Write-Host "$message" -ForegroundColor Yellow
        $null = (Get-Host).UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}

function Write-HostCenter { 
    param(
        [String]$Message,
        [String]$Colour) 
    
    If ($Colour) {
        Write-Host ("{0}{1}" -f (' ' * (([Math]::Max(0, (Get-Host).UI.RawUI.BufferSize.Width / 2) - [Math]::Floor($Message.Length / 2)))), $Message) -ForegroundColor $Colour
    } Else {
        Write-Host ("{0}{1}" -f (' ' * (([Math]::Max(0, (Get-Host).UI.RawUI.BufferSize.Width / 2) - [Math]::Floor($Message.Length / 2)))), $Message) 
    }
}

# Function to attempt to repair a video object with ffmpeg.exe if -AutoRepair is selected
Function RepairFile {
    Param ([Object]$VideoFile)

    # Get only the file name of the Video Object
    $RepairFileName = $VideoFile.Name

    # Get only the file name without the extension of the video object and remove the brackets
    $RepairFileBaseName = $VideoFile.BaseName -replace '[][]', ''

    # Get all the variables to create the another file in the same directory with _repaired in the filename
    $dir = $VideoFile.DirectoryName
    $RepairVFileName = "$RepairFileBaseName" + "_repaired.$global:RepairVFileExtension"
    $RepairFullName = Join-Path -path $dir -ChildPath $RepairVFileName

    If (!(Test-Path -LiteralPath $RepairFullName)) {
        LogWrite "Creating Repair File: $RepairFullName" -Log

        $RepairFileName = $RepairFileName -replace '[][]', ''
        $RepairFileName = $RepairFileName + "_repair.log"
    
        $errorLog = Join-Path -path $LogPath -childpath $RepairFileName
    
        # Attempt to repair the video file with ffmpeg
        If ($global:LimitCPU) {
            ffmpeg.exe -y -i $VideoFile.FullName -max_muxing_queue_size 1024 -c:v $global:VideoLibrary -crf $global:CRF -c:a aac -q:a 100 -strict -2 -threads $global:CPULimt -movflags faststart -level 41 $RepairFullName 2> $errorLog
        }
        Else {
            ffmpeg.exe -y -i $VideoFile.FullName -max_muxing_queue_size 1024 -c:v $global:VideoLibrary -crf $global:CRF -c:a aac -q:a 100 -strict -2 -movflags faststart -level 41 $RepairFullName 2> $errorLog
        }
    
        # Check to see if the repaired file still has errors
        $RepairFile = Get-Item $RepairFullName
    
        # Check the scan history file to see if the file has been scanned
        $scanHistoryCheck = (Get-Content $scanHistory | Select-String -pattern $RepairFile.FullName -SimpleMatch)
    
        If ($RepairFile.Name.Length -lt 1) {
            LogWrite "There was an issue creating the repaired file with FFMPEG" -Log
        }
        ElseIf ($null -ne $scanHistoryCheck) {
            CheckFile $RepairFile -AutoRepaired -RescanVideo
        }
        Else {
            CheckFile $RepairFile -AutoRepaired
        }
    } Else {
        LogWrite "Skipping repair: Repaired File already exists." -Log
        LogWrite "Repair file found: $RepairFullName" -Log
        $OriginalFile = Get-ChildItem -LiteralPath $global:OriginalFile.FullName
        Update-VideoArray -VideoFile $OriginalFile -Status "Failed" -Update
        Write-ScanOutput
    }
}

# Function to check a supplied video object with ffmpeg.exe
Function CheckFile {
    Param (
        [Object]$VideoFile,
        [switch]$AutoRepaired,
        [switch]$RescanVideo
    )

    # If the file is a new file being check, clear out the variables
    If (!($AutoRepaired)) {
        $global:RepairLength = $null
        $global:RepairedFile = $null
        $global:OrigLength = $null
        $global:OriginalFile = $null
    }

    # Reset the Deleted value
    $Deleted = $false

    # Get the full name of the Video Object with path included
    $fullName = $VideoFile.FullName

    # Get only the name of the video file
    $fileName = $VideoFile.Name

    # Counter for the number of files that have been scanned
    $global:VideoCount = $global:VideoCount + 1

    # Save the length and object of the video file to make sure the repaired video file length matches original
    If ($AutoRepaired) {
        $global:RepairLength = GetLength $VideoFile
        $global:RepairedFile = $VideoFile
    }
    Else {
        $global:OrigLength = GetLength $VideoFile
        $global:OriginalFile = $VideoFile
    }

    If ($RescanVideo) {
        Update-VideoArray -VideoFile $VideoFile -Status "Re-Scanning"
    } Else {
        Update-VideoArray -VideoFile $VideoFile -Status "Scanning"
    }
    
    LogWrite "Scanning File: $fullName" -Log
    Write-ScanOutput -Scanning

    If (Test-Path $ffmpegLog) {
        Try {
            Remove-Item -LiteralPath $ffmpegLog -Force
        } Catch {
            $ErrorMessage = $_.Exception.Message
            LogWrite "Error while removing old FFMPEG Log: $ErrorMessage" -Colour "Red"
            LogWrite "Scan cannot continue without the ability to modify: $ffmpegLog"
            Exit 1 
        }
    }

    # Scan the file with FFMPEG
    If ($global:LimitCPU) {
        ffmpeg.exe -v error -i $fullName -max_muxing_queue_size 1024 -f null -threads $global:CPULimt - >$ffmpegLog 2>&1
    }
    Else {
        ffmpeg.exe -v error -i $fullName -max_muxing_queue_size 1024 -f null - >$ffmpegLog 2>&1
    }

    # Check to see if the ffmpeg error log was empty
    If ($Null -eq (Get-Content $ffmpegLog)) {   
        # Get information to log to the CSV file
        $FileSize = "{0:N2}" -f (($VideoFile | Measure-Object -property length -sum ).sum / 1MB)
        $Date = $((Get-Date).ToString('yyyy-MM-dd'))

        # If the file is an Auto-Repaired File
        If ($AutoRepaired) {  
            # File is only repaired successfully if the video file length matches original
            If (($global:RepairLength -eq $global:OrigLength) -and ($Null -ne $global:RepairLength)) {
                LogWrite "File Repaired Successfully: $fullName" -Log
                Update-VideoArray -VideoFile $VideoFile -Status "Passed" -Update
                Write-ScanOutput
                Write-CSV -VidfileName $fileName -VidfilePath $fullName -TestResults "Passed" -Date $Date -VidFileSize $FileSize -VidLength $RepairLength
                $OriginalFile = Get-ChildItem -LiteralPath $global:OriginalFile.FullName
                Update-VideoArray -VideoFile $OriginalFile -Status "Failed" -Update
                Write-ScanOutput

                If ($global:RemoveOriginal -or $global:RemoveAll -or $global:TrashEnabled) {
                    # Remove the original file and rename the repair file 
                    Try {
                        If ($global:TrashEnabled) {
                            LogWrite "Moving the original file: $($global:OriginalFile.Name)" -Log
                            Move-Item -LiteralPath $global:OriginalFile.FullName -Destination $global:TrashEnabled -Force
                            Update-VideoArray -VideoFile $OriginalFile -Status "Moved" -Update
                        } Else {
                            LogWrite "Deleting the original file: $($global:OriginalFile.Name)" -Log
                            Get-ChildItem -LiteralPath $global:OriginalFile.FullName -File | Remove-Item -Force -ErrorAction Stop
                            Update-VideoArray -VideoFile $OriginalFile -Status "Deleted" -Update
                        }
                        Write-ScanOutput
                        LogWrite "Renaming Repaired file to Original File" -Log
                        $NewFileName = $global:OriginalFile.BaseName + $global:RepairedFile.Extension
                        Update-VideoArray -VideoFile $VideoFile -Status "Passed:Renamed" -Update
                        Write-ScanOutput
                        Rename-Item -Path $global:RepairedFile.FullName -NewName $NewFileName -ErrorAction Stop
                        $Deleted = $true
                        $global:OriginalRemoved = $true
                    }
                    Catch {
                        $ErrorMessage = $_.Exception.Message
                        LogWrite "Error: $ErrorMessage" -Log
                    }
                }
            }
            Else {
                LogWrite "ERROR: Error Found in Repaired File. Video Length does not match Original: $fullName" -Log
                LogWrite "Estimate of error location in Original File: $global:RepairLength" -Log
                Update-VideoArray -VideoFile $VideoFile -Status "Failed" -Update
                $OriginalFile = Get-ChildItem -LiteralPath $global:OriginalFile.FullName
                Update-VideoArray -VideoFile $OriginalFile -Status "Failed" -Update
                Write-ScanOutput
                $global:RepairedErrorList.Add($fileName) | Out-Null
                Write-CSV -VidfileName $fileName -VidfilePath $fullName -TestResults "Failed" -Date $Date -VidFileSize $FileSize -VidLength $RepairLength

                If ($global:RemoveAll -or $global:RemoveRepaired) {
                    LogWrite "Deleting Repaired File: $fileName" -Log
                    Update-VideoArray -VideoFile $VideoFile -Status "Deleted" -Update
                    Write-ScanOutput
                    Get-ChildItem -LiteralPath $VideoFile.FullName -File | Remove-Item -Force -ErrorAction Stop
                    $Deleted = $true
                }
            }
        # If the file is not an Auto-Repaired file
        }
        Else { 
            LogWrite "Scanned Successfully: $fullName" -Log
            Update-VideoArray -VideoFile $VideoFile -Status "Passed" -Update
            Write-ScanOutput
            Write-CSV -VidfileName $fileName -VidfilePath $fullName -TestResults "Passed" -Date $Date -VidFileSize $FileSize -VidLength $OrigLength
        }

        # If the video file is not a re-scanned file, add it to the scan history
        If (!$RescanVideo) {
            #If the video has been deleted, do not log the file name in scanHistory file for scanning again at a later time.
            If (!($Deleted)) {
                Add-content $scanHistory $fullName
            }
        }

        # Check to see if the ffmpeg error log was not empty
    }
    Elseif ($Null -ne (Get-Content $ffmpegLog)) {
        # Get information to log to the CSV file
        $FileSize = "{0:N2}" -f (($VideoFile | Measure-Object -property length -sum ).sum / 1MB)
        $Date = $((Get-Date).ToString('yyyy-MM-dd'))

        If ($AutoRepaired) {  
            LogWrite "ERROR: Error found in Repaired File: $fullName" -Log
            Update-VideoArray -VideoFile $VideoFile -Status "Failed" -Update
            Write-ScanOutput
            Write-CSV -VidfileName $fileName -VidfilePath $fullName -TestResults "Failed" -Date $Date -VidFileSize $FileSize -VidLength $RepairLength
            $global:RepairedErrorList.Add($fileName) | Out-Null

            If ($global:RemoveAll -or $global:RemoveRepaired) {
                LogWrite "Deleting Repaired File: $fileName" -Log
                Update-VideoArray -VideoFile $VideoFile -Status "Deleted" -Update
                Write-ScanOutput
                Get-ChildItem -LiteralPath $VideoFile.FullName -File | Remove-Item -Force -ErrorAction Stop
                $Deleted = $true
            }
        }
        else {
            LogWrite "ERROR: Error found: $fullName" -Log
            Update-VideoArray -VideoFile $VideoFile -Status "Failed" -Update
            Write-ScanOutput
            $global:ErrorList.Add($fileName) | Out-Null
            Write-CSV -VidfileName $fileName -VidfilePath $fullName -TestResults "Failed" -Date $Date -VidFileSize $FileSize -VidLength $OrigLength
        }

        $fileName = $fileName -replace '[][]', ''
        $fileName = $fileName + "_error.log"
        $errorLog = Join-Path -path $LogPath  -ChildPath $fileName

        If (Test-Path $errorLog) {
            LogWrite "Removing Error Log : $errorLog" -Log
            Remove-Item -Path $errorLog
        }

        Try {
            Rename-Item $ffmpegLog $errorLog
        }
        Catch {
            $ErrorMessage = $_.Exception.Message
            LogWrite "ERROR: Failed to rename the ffmpeg log: $ErrorMessage" -Log
            LogWrite $ErrorMessage -Log
            $errorLog = Join-Path -path $LogPath -childpath "GenericError.log"
            Get-Content $ffmpegLog | Add-Content $errorLog
            Remove-item $ffmpegLog
        }

        # Only continue if the file is not already flagged as auto-repaired
        if (!$AutoRepaired) {
            # Only continue if auto-repair is selected
            if ($global:AutoRepair) {
                Update-VideoArray -VideoFile $VideoFile -Status "Repairing" -Update
                Write-ScanOutput -Repairing
                LogWrite "Attempting to Repair : $VideoFile" -Log
                # Supply the video object to the repair function
                RepairFile $VideoFile
            }
        }

        If ($global:RemoveAll -or $global:TrashEnabled) {
            # Remove the original file even if the repair was not successful
            If (!($AutoRepaired)) {
                If ($global:OriginalRemoved -eq $false) {
                    If ($global:TrashEnabled) {
                        LogWrite "Moving the original file: $($VideoFile.Name)" -Log
                        Move-Item -LiteralPath $VideoFile.FullName -Destination $global:TrashEnabled -Force
                        Update-VideoArray -VideoFile $VideoFile -Status "Moved" -Update
                        Write-ScanOutput
                        $Deleted = $true
                    } Else {
                        LogWrite "Deleting the original file: $($VideoFile.Name)" -Log
                        Update-VideoArray -VideoFile $VideoFile -Status "Deleted" -Update
                        Write-ScanOutput
                        Get-ChildItem -LiteralPath $VideoFile.FullName -File | Remove-Item -Force -ErrorAction Stop
                        $Deleted = $true
                    }
                }
                $global:OriginalRemoved = $false
            }
        }

        # If the video file is not a re-scanned file, add it to the scan history
        If (!$RescanVideo) {
            #If the video has been deleted, do not log the file name in scanHistory file for scanning again at a later time.
            If (!($Deleted)) {
                # Get the updated Original file name if the file was repaired
                $NewFileName = Join-Path -Path $global:OriginalFile.DirectoryName -ChildPath $global:OriginalFile.BaseName
                $NewFileName = $NewFileName + $global:RepairedFile.Extension
                Try {
                    $NewFileObject = Get-ChildItem -LiteralPath $NewFileName -File -ErrorAction Stop
                }
                Catch {
                    # If no matches are found, do nothing
                }
                If ($NewFileObject) {
                    Add-Content $scanHistory $NewFileObject.FullName
                }
                Else {
                    Add-Content $scanHistory $fullName
                }
            }
        }
    }
}

Function GetLength {
    Param ([Object]$VideoFile)

    $LengthColumn = 27
    $objShell = New-Object -ComObject Shell.Application 
    $objFolder = $objShell.Namespace($VideoFile.DirectoryName)
    $objFile = $objFolder.ParseName($VideoFile.Name)
    $VideoLength = $objFolder.GetDetailsOf($objFile, $LengthColumn) 

    return $VideoLength
}

Function Write-CSV {
    Param (
        [String]$VidfileName,
        [String]$VidfilePath,
        [String]$TestResults,
        [String]$Date,
        [String]$VidFileSize,
        [String]$VidLength
    )

    $VidfileName = $VidfileName -replace ',', ''
    $VidfilePath = $VidfilePath -replace ',', ''
    $VidFileSize = $VidFileSize -replace ',', ''

    $CSVContent = "$VidfileName,$TestResults,$Date,$VidFileSize,$VidLength,$VidfilePath"
    try {
        Add-content $CSVfile -Value $CSVContent
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        LogWrite "ERROR: Failed to log the result to the csv file $CSVfile" -Colour "Red"
        LogWrite $ErrorMessage -Log
    }
}

Function Get-YesNoResponse {
    Param (
        [String]$Message
    )
    $MenuChoice = "n"
    Write-Host $Message -ForegroundColor Cyan
    while ($MenuChoice -ne "y") {
        Write-Host "Choice [Default: n]: " -ForegroundColor Cyan -NoNewline
        $MenuChoice = Read-Host
        If ([string]::IsNullOrEmpty($MenuChoice)) {
            $MenuChoice = "n"
        }
        If ($MenuChoice -eq "n") {
            return $false
        }
        ElseIf ($MenuChoice -eq "y") {
            return $true
        }
    }
}

Function Get-MenuResponse {
    Param (
        [String]$Message,
        [String]$Options
    )
    $MenuChoice = 0
    Write-Host $Message -ForegroundColor Cyan
    $OptionArray = $Options.Split(";")
    $OptionNumber = 1
    ForEach ($Option in $OptionArray) {
        Write-Host " $($OptionNumber): $Option"
        $OptionNumber++
    }
    while ($MenuChoice -lt 1 -or $MenuChoice -gt ($OptionNumber - 1)) {
        Write-Host "Choice Number: " -ForegroundColor Cyan -NoNewline
        $MenuChoice = Read-Host
    }
    return $MenuChoice
}


Function Show-Menu {
    $MenuChoice = 0
    Write-Host ""
    Write-Host "-------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "                     Main Menu" -ForegroundColor Yellow
    Write-Host "-------------------------------------------------------" -ForegroundColor Yellow
    Write-Host " 1:  Quick Scan"
    Write-Host " 2:  Default Scan"
    Write-Host " 3:  Background Scan"
    Write-Host " 4:  Create a Configuration file for automated scanning"
    Write-Host " 5:  FFMPEG Utilities"
    Write-Host " 6:  Help Menu"
    Write-Host ""
    Write-Host "Please make a selection from the Menu Choices." -ForegroundColor Cyan 

    while ($MenuChoice -lt 1 -or $MenuChoice -gt 6) {
        Write-Host "Choice Number: " -ForegroundColor Cyan -NoNewline
        $MenuChoice = Read-Host
    }

    switch ($MenuChoice) {
        1 { 
            Get-MediaPath -ScanType "Quick"
            Select-ScanOptions -ScanType "Quick"
        }
        2 { 
            Get-MediaPath -ScanType "Default"
            Select-ScanOptions -ScanType "Default"
        }
        3 { 
            Get-MediaPath -ScanType "Background"
            Select-ScanOptions -ScanType "Background"
        }
        4 { 
            New-Configuration
        }
        5 { 
            Show-FFMPEGUtilities
        }
        6 { 
            Show-Help
        }
    }
}

Function Get-OnlineVersion {
    # Update Check function
    Try {
        $WebResponse = Invoke-WebRequest "https://gist.githubusercontent.com/Desani/129be27da7d735d7c75192ec1aa96c65/raw/ScanMedia.ps1" -UseBasicParsing
        ForEach ($Line in $WebResponse.Content.Split([Environment]::NewLine)) {
            If ($Line.Contains("ScriptVersion =") -and (!($Line.Contains("Line.Contains")))) {
                $VersionString = $Line 
            }
        }
        $pos = $VersionString.IndexOf("=")
        [float]$OnlineVersion = $VersionString.Substring($pos + 1)
        If ($OnlineVersion -gt $ScriptVersion) {
            Write-Host ""
            Write-HostCenter "*****************************************************************************" -Colour Green
            Write-HostCenter "A new version is available for download. New Version: $OnlineVersion" -Colour Green
            Write-HostCenter "Please update your script to the latest version at your earliest convenience" -Colour Green
            Write-HostCenter "*****************************************************************************" -Colour Green
            Write-Host ""
        }
    }
    Catch {
        $ErrorMessage = $_.Exception.Message
        Write-Verbose "There was an issue checking online for new version"
        Write-Verbose $ErrorMessage
    }
}

Function Get-MediaPath {
    Param (
        [String]$ScanType
    )
    Clear-Host
    Write-Host ""
    Write-Host "-------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "                   $ScanType Scan" -ForegroundColor Yellow
    Write-Host "-------------------------------------------------------" -ForegroundColor Yellow
    Write-Host ""

    If ($global:Path) {
        If (!(Test-Path $global:Path)) {
            $PathDir = "InvalidPath:\"
            Write-Host "The supplied Path folder for scanning files is invalid: $global:Path" -ForegroundColor Red
            While (!(Test-Path -LiteralPath $PathDir)) {
                Write-Host "Please enter the path that you would like to scan media files:" -ForegroundColor Cyan
                Write-Host "Note: This path should be always accessible by the System so that files can be scanned" -ForegroundColor Yellow
                Write-Host "Example: X:\Movies or Z:\Videos\Render.mp4"
                while ($PathDir -eq "InvalidPath:\") {
                    Write-Host "Path: " -ForegroundColor Cyan -NoNewline
                    $PathDir = Read-Host
                }
                If (!(Test-Path -LiteralPath $PathDir)) {
                    Write-Host "Error: The path supplied is invalid."
                    $PathDir = "InvalidPath:\"
                }
            }
            $global:Path = $PathDir
        }
        Write-Host "Using supplied path: $global:Path" -ForegroundColor Cyan
    }
    Else {
        $global:Path = "InvalidPath:\"
        While (!(Test-Path -LiteralPath $global:Path)) {
            Write-Host "Please enter the path that you would like to use to scan:" -ForegroundColor Cyan
            Write-Host "Example: X:\Movies or Z:\Videos\Render.mp4"
            while ($global:Path -eq "InvalidPath:\") {
                Write-Host "Path: " -ForegroundColor Cyan -NoNewline
                $global:Path = Read-Host
            }
            If (!(Test-Path -LiteralPath $global:Path)) {
                Write-Host "Error: The path supplied is invalid."
                $global:Path = "InvalidPath:\"
            } 
        }
    }

    If ($global:TrashEnabled) {
        If (!(Test-Path $global:TrashEnabled)) {
            $TrashDir = "InvalidPath:\"
            Write-Host "The supplied Trash folder for corrupt video files is invalid: $global:TrashEnabled" -ForegroundColor Red
            While (!(Test-Path -LiteralPath $TrashDir)) {
                Write-Host "Please enter the path that you would like to store videos with errors:" -ForegroundColor Cyan
                Write-Host "Note: This path should be always accessible by the System so that files can be moved" -ForegroundColor Yellow
                Write-Host "Example: C:\BadVideos or D:\Media\Temp"
                while ($TrashDir -eq "InvalidPath:\") {
                    Write-Host "Path: " -ForegroundColor Cyan -NoNewline
                    $TrashDir = Read-Host
                }
                If (!(Test-Path -LiteralPath $TrashDir)) {
                    Write-Host "Error: The path supplied is invalid."
                    $TrashDir = "InvalidPath:\"
                }
                If ($TrashDir.Contains("[") -or $TrashDir.Contains("]")) {
                    Write-Host "Error: The path supplied is contains the characters [ or ]. Please supply a path that does not contain square brackets."
                    $TrashDir = "InvalidPath:\"
                } 
            }
            $global:TrashEnabled = $TrashDir
        }
        Write-Host "Using the Trash Directory: $global:TrashEnabled"
    }
}

Function Select-ScanOptions {
    Param (
        [String]$ScanType
    )

    switch ($ScanType) {
        { $_ -match "Quick" } {
            $global:Rescan = $true
        }
        { $_ -match "Default" } {
            If (!($global:Rescan)) {
                $global:Rescan = Get-YesNoResponse "Would you like to re-scan files that have already been scanned? (y/n)"
            }

            If (!($global:LimitCPU)) {
                $global:LimitCPU = Get-YesNoResponse "Would you like to Limit FFMPEG CPU's core usage? (y/n)"
            }

            If (!($global:AutoRepair)) {
                $global:AutoRepair = Get-YesNoResponse "Would you like to attempt to auto-repair damaged files? (y/n)"
            }

            If ((!($global:RemoveAll)) -and (!($global:RemoveRepaired)) -and (!($global:RemoveOriginal))) {
                $MenuChoice = Get-YesNoResponse "Would you like to delete failed files? (y/n)"
                If ($MenuChoice -eq "y") {
                    $Choice = Get-MenuResponse -Message "What failed files would you like to remove?" -Options "Failed Repaired Files;Failed Original Files;All Failed Files;No Deletions"
                    switch ($Choice) {
                        1 { $global:RemoveRepaired = $true }
                        2 { $global:RemoveOriginal = $true }
                        3 { $global:RemoveAll = $true }
                        4 {  }
                    }
                }
            }
            If (!($global:TrashEnabled)) {
                $TrashEnabled = Get-YesNoResponse "Would you like to enabled the trash folder and send files with errors to this folder? (y/n)"
                If ($TrashEnabled) {
                    $TrashDir = "InvalidPath:\"
                    While (!(Test-Path -LiteralPath $TrashDir)) {
                        Write-Host "Please enter the path that you would like to store videos with errors:" -ForegroundColor Cyan
                        Write-Host "Note: This path should be always accessible by the System so that files can be moved" -ForegroundColor Yellow
                        Write-Host "Example: C:\BadVideos or D:\Media\Temp"
                        while ($TrashDir -eq "InvalidPath:\") {
                            Write-Host "Path: " -ForegroundColor Cyan -NoNewline
                            $TrashDir = Read-Host
                        }
                        If (!(Test-Path -LiteralPath $TrashDir)) {
                            Write-Host "Error: The path supplied is invalid."
                            $TrashDir = "InvalidPath:\"
                        }
                        If ($TrashDir.Contains("[") -or $TrashDir.Contains("]")) {
                            Write-Host "Error: The path supplied is contains the characters [ or ]. Please supply a path that does not contain square brackets."
                            $TrashDir = "InvalidPath:\"
                        } 
                    }
                    $global:TrashEnabled = $TrashDir
                }
            }
        }
        { $_ -match "Background" } {
            # Auto Limit CPU usage for a background scan
            $global:LimitCPU = $true

            If (!($global:IdleScan)) {
                $global:IdleScan = Get-YesNoResponse "Would you like to limit scanning to only when the CPU is not being used by other processes? (y/n)"
            }

            If (!($global:Rescan)) {
                $global:Rescan = Get-YesNoResponse "Would you like to re-scan files that have already been scanned? (y/n)"
            }
            If (!($global:AutoRepair)) {
                $global:AutoRepair = Get-YesNoResponse "Would you like to attempt to auto-repair damaged files? (y/n)"
            }
            If ((!($global:RemoveAll)) -and (!($global:RemoveRepaired)) -and (!($global:RemoveOriginal))) {
                $MenuChoice = Get-YesNoResponse "Would you like to delete failed files? (y/n)"
                If ($MenuChoice -eq "y") {
                    $Choice = Get-MenuResponse -Message "What failed files would you like to remove?" -Options "Failed Repaired Files;Failed Original Files;All Failed Files;No Deletions"
                    switch ($Choice) {
                        1 { $global:RemoveRepaired = $true }
                        2 { $global:RemoveOriginal = $true }
                        3 { $global:RemoveAll = $true }
                        4 {  }
                    }
                }
            }
            If (!($global:ContinuousScan)) {
                $global:ContinuousScan = Get-YesNoResponse "Would you like to setup the scan to run continuously in the background? (y/n)"
            }
            If (!($global:TrashEnabled)) {
                $TrashEnabled = Get-YesNoResponse "Would you like to enabled the trash folder and send files with errors to this folder? (y/n)"
                If ($TrashEnabled) {
                    $TrashDir = "InvalidPath:\"
                    While (!(Test-Path -LiteralPath $TrashDir)) {
                        Write-Host "Please enter the path that you would like to store videos with errors:" -ForegroundColor Cyan
                        Write-Host "Note: This path should be always accessible by the System so that files can be moved" -ForegroundColor Yellow
                        Write-Host "Example: C:\BadVideos or D:\Media\Temp"
                        while ($TrashDir -eq "InvalidPath:\") {
                            Write-Host "Path: " -ForegroundColor Cyan -NoNewline
                            $TrashDir = Read-Host
                        }
                        If (!(Test-Path -LiteralPath $TrashDir)) {
                            Write-Host "Error: The path supplied is invalid."
                            $TrashDir = "InvalidPath:\"
                        }
                        If ($TrashDir.Contains("[") -or $TrashDir.Contains("]")) {
                            Write-Host "Error: The path supplied is contains the characters [ or ]. Please supply a path that does not contain square brackets."
                            $TrashDir = "InvalidPath:\"
                        } 
                    }
                    $global:TrashEnabled = $TrashDir
                }
            }
        }
    }
    New-MediaScan
}

Function New-Configuration {

    $ConfigList = New-Object System.Collections.ArrayList

    Clear-Host
    Write-Host ""
    Write-HostCenter "-------------------------------------------------------" -Colour Yellow
    Write-HostCenter "Write a new Configuration" -Colour Yellow
    Write-HostCenter "-------------------------------------------------------" -Colour Yellow
    Write-Host ""
    Write-Host (Write-WrapString "In this section you will be given a series of questions that will be used to generate a configuration JSON file. This file can be used with the -ConfigFile parameter to setup automated scanning.")

    $Path = "InvalidPath:\"
    While (!(Test-Path -LiteralPath $Path)) {
        Write-Host "Please enter the path that you would like to use to scan:" -ForegroundColor Cyan
        Write-Host "Example: X:\Movies or Z:\Videos\Render.mp4"
        while ($Path -eq "InvalidPath:\") {
            Write-Host "Path: " -ForegroundColor Cyan -NoNewline
            $Path = Read-Host
        }
        If (!(Test-Path -LiteralPath $Path)) {
            Write-Host "Error: The path supplied is invalid."
            $Path = "InvalidPath:\"
        } 
    }
    $ConfigItem = New-Object PSObject -Property @{Name="Path";Value=$Path}
    $ConfigList.Add($ConfigItem) | Out-Null

    $LogDir = "InvalidPath:\"
    While (!(Test-Path -LiteralPath $LogDir)) {
        Write-Host "Please enter the path that you would like to store the log files:" -ForegroundColor Cyan
        Write-Host "Note: This path should be always accessible by the System so that errors can be logged" -ForegroundColor Yellow
        Write-Host "Example: C:\ScanLogs or D:\Media\ScanLogs"
        while ($LogDir -eq "InvalidPath:\") {
            Write-Host "Path: " -ForegroundColor Cyan -NoNewline
            $LogDir = Read-Host
        }
        If (!(Test-Path -LiteralPath $LogDir)) {
            Write-Host "Error: The path supplied is invalid."
            $LogDir = "InvalidPath:\"
        }
        If ($LogDir.Contains("[") -or $LogDir.Contains("]")) {
            Write-Host "Error: The path supplied is contains the characters [ or ]. Please supply a path that does not contain square brackets."
            $LogDir = "InvalidPath:\"
        } 
    }
    $ConfigItem = New-Object PSObject -Property @{Name="LogDir";Value=$LogDir}
    $ConfigList.Add($ConfigItem) | Out-Null

    $IdleScan = Get-YesNoResponse "Would you like to limit scanning to only when the CPU is not being used by other processes? (y/n)"
    $ConfigItem = New-Object PSObject -Property @{Name="IdleScan";Value=$IdleScan}
    $ConfigList.Add($ConfigItem) | Out-Null

    $LimitCPU = Get-YesNoResponse "Would you like to Limit FFMPEG CPU's core usage? (y/n)"
    $ConfigItem = New-Object PSObject -Property @{Name="LimitCPU";Value=$LimitCPU}
    $ConfigList.Add($ConfigItem) | Out-Null

    $Rescan = Get-YesNoResponse "Would you like to re-scan files that have already been scanned? (y/n)"
    $ConfigItem = New-Object PSObject -Property @{Name="Rescan";Value=$Rescan}
    $ConfigList.Add($ConfigItem) | Out-Null

    $AutoRepair = Get-YesNoResponse "Would you like to attempt to auto-repair damaged files? (y/n)"
    $ConfigItem = New-Object PSObject -Property @{Name="AutoRepair";Value=$AutoRepair}
    $ConfigList.Add($ConfigItem) | Out-Null
    If ($AutoRepair) {
        $CRF = $null
        Write-Host "What CRF value would you like to use for Repaired Video Encodes?" -ForegroundColor Cyan
        Write-Host "Must be a value between 0 and 51"
        While (($CRF -lt 0) -or ($CRF -gt 51)) {
            Write-Host "Choice Number [Default: 21]: " -ForegroundColor Cyan -NoNewline
            $CRF = Read-Host
            If ([string]::IsNullOrEmpty($CRF)) {
                $CRF = 21
            }
        }
    } Else {
        $CRF = 21
    }
    $ConfigItem = New-Object PSObject -Property @{Name="CRF";Value=$CRF}
    $ConfigList.Add($ConfigItem) | Out-Null

    $Delete = Get-YesNoResponse "Would you like to delete failed files? (y/n)"
    If ($Delete -eq "y") {
        $Choice = Get-MenuResponse -Message "What failed files would you like to remove?" -Options "Failed Repaired Files;Failed Original Files;All Failed Files;No Deletions"
        switch ($Choice) {
            1 { $RemoveRepaired = $true }
            2 { $RemoveOriginal = $true }
            3 { $RemoveAll = $true }
            4 {  }
        }
    } Else {
        $RemoveRepaired = $false
        $RemoveOriginal = $false
        $RemoveAll = $false
    }
    If ($RemoveRepaired -or $RemoveAll -or $RemoveOriginal) {

        $Acceptance = ""

        Write-Host "************************* WARNING *******************************" -ForegroundColor Red
        Write-Host "The commands supplied have the ability to delete original files" -ForegroundColor Yellow
        Write-Host "A backup is highly recommended when supplying these commands" -ForegroundColor Yellow
        Write-Host "Please type the following confirm you understand: IACCEPT" -ForegroundColor Yellow
        Write-Host "************************* WARNING *******************************" -ForegroundColor Red

        while ($Acceptance -ne "IACCEPT") {
            Write-Host "Please Type the above command: " -ForegroundColor Magenta -NoNewline
            $Acceptance = Read-Host
        }
    }
    $ConfigItem = New-Object PSObject -Property @{Name="RemoveRepaired";Value=$RemoveRepaired}
    $ConfigList.Add($ConfigItem) | Out-Null
    $ConfigItem = New-Object PSObject -Property @{Name="RemoveOriginal";Value=$RemoveOriginal}
    $ConfigList.Add($ConfigItem) | Out-Null
    $ConfigItem = New-Object PSObject -Property @{Name="RemoveAll";Value=$RemoveAll}
    $ConfigList.Add($ConfigItem) | Out-Null

    $ContinuousScan = Get-YesNoResponse "Would you like to setup the scan to run continuously in the background? (y/n)"
    $ConfigItem = New-Object PSObject -Property @{Name="ContinuousScan";Value=$ContinuousScan}
    $ConfigList.Add($ConfigItem) | Out-Null

    $TrashEnabled = Get-YesNoResponse "Would you like to enabled the trash folder and send files with errors to this folder? (y/n)"
    If ($TrashEnabled) {
        $TrashDir = "InvalidPath:\"
        While (!(Test-Path -LiteralPath $TrashDir)) {
            Write-Host "Please enter the path that you would like to store videos with errors:" -ForegroundColor Cyan
            Write-Host "Note: This path should be always accessible by the System so that files can be moved" -ForegroundColor Yellow
            Write-Host "Example: C:\BadVideos or D:\Media\Temp"
            while ($TrashDir -eq "InvalidPath:\") {
                Write-Host "Path: " -ForegroundColor Cyan -NoNewline
                $TrashDir = Read-Host
            }
            If (!(Test-Path -LiteralPath $TrashDir)) {
                Write-Host "Error: The path supplied is invalid."
                $TrashDir = "InvalidPath:\"
            }
            If ($TrashDir.Contains("[") -or $TrashDir.Contains("]")) {
                Write-Host "Error: The path supplied is contains the characters [ or ]. Please supply a path that does not contain square brackets."
                $TrashDir = "InvalidPath:\"
            } 
        }
        $ConfigItem = New-Object PSObject -Property @{Name="TrashEnabled";Value=$TrashDir}
        $ConfigList.Add($ConfigItem) | Out-Null
    }
    
    Write-Host "Generating Configuration INI file"
    Try {
        $ConfigList | ConvertTo-Json | Set-Content $LogDir\ScanConfig-$Date.json -Force -ErrorAction Stop
        $JSONPath = Join-Path -Path $LogDir -ChildPath "ScanConfig-$Date.json"
        Write-Host "Configuration Successfully Saved in: $JSONPath"
        Write-Host "Please test the new configuration out by using the command: .\ScanMedia.ps1 -ConfigFile $JSONPath"
    } Catch {
        $ErrorMessage = $_.Exception.Message
        Write-Verbose "Error. There was an issue generating the JSON file."
        Write-Verbose $ErrorMessage
    }
}

Function Show-FFMPEGUtilities {
    Clear-Host
    Write-Host ""
    Write-HostCenter "-------------------------------------------------------" -Colour Yellow
    Write-HostCenter "FFMPEG Utilities" -Colour Yellow
    Write-HostCenter "-------------------------------------------------------" -Colour Yellow
    Write-Host ""
    Write-Host "ScanMedia Script utilizes FFMPEG to scan each video. It will need to be accessible by the script by adding the location to the Environmental Variable PATH or by placing ffmpeg.exe in the same directory as the script"
    Write-Host "This menu can be used to attempt to download the newest version essentials edition and unpack it for use with this script"
    Write-Host ""
    Write-Host " 1:  Check ffmpeg.exe access from script"
    Write-Host " 2:  Download latest version of ffmpeg-release-essentials.zip"
    Write-Host " 3:  Main Menu"
    Write-Host ""
    Write-Host "Please make a selection from the Menu Choices." -ForegroundColor Cyan 

    $MenuChoice = 0
    while ($MenuChoice -lt 1 -or $MenuChoice -gt 3) {
        Write-Host "Choice Number: " -ForegroundColor Cyan -NoNewline
        $MenuChoice = Read-Host
    }

    switch ($MenuChoice) {
        1 { 
            If ($null -eq (Get-Command "ffmpeg.exe" -ErrorAction SilentlyContinue)) { 
                Write-Host "ERROR: Unable to find ffmpeg.exe on the computer or in the local script directory" -ForegroundColor "Red"
                Write-Host "Please download ffmpeg and place ffmpeg.exe in: $scriptPath or use the downloader in the FFMPEG Utilities Menu" -ForegroundColor "Cyan"
                Write-PauseMessage "Press a key to continue..."
                Show-FFMPEGUtilities
            } Else {
                Write-PauseMessage "Success! ffmpeg.exe is usable by this script. Press a key to continue..."
                Show-FFMPEGUtilities
            }
         }
        2 {  
            $Url = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
            Write-Host "Attempting to download ffmpeg-release-essentials.zip from $Url"
            Try {
                $ZipFile = Join-Path -Path $scriptPath -ChildPath "ffmpeg-release-essentials.zip"
                If (Test-Path $ZipFile) {
                    Write-Host "Removing previous ffmpeg-release-essentials.zip download"
                    Remove-Item -Path $ZipFile -Force -ErrorAction Stop
                }
                Invoke-WebRequest -Uri $Url -OutFile $ZipFile -UseBasicParsing -ErrorAction Stop

                $Destination = Join-Path -Path $scriptPath -ChildPath "FFMPEG"
                If (Test-Path $Destination) {
                    Write-Host "Removing previous un-packed zip folder"
                    Remove-Item -Path $Destination -Force -Recurse -ErrorAction Stop
                }
                Write-Host "Unpacking Zip File..."
                Expand-Archive -LiteralPath $ZipFile -DestinationPath $Destination -ErrorAction Stop

                $ExeFile = Join-Path -Path $scriptPath -ChildPath "ffmpeg.exe"
                If (Test-Path $ExeFile) {
                    Write-Host "Removing previous ffmpeg.exe executable"
                    Remove-Item -Path $ExeFile -Force -ErrorAction Stop
                }
                Write-Host "Copying ffmpeg.exe to $scriptPath"
                $ffmpegFolder = Join-Path -Path $Destination -ChildPath "ffmpeg*essentials_build"
                $GetFolder = Get-Item -Path $ffmpegFolder

                $FFMPEGLocation = Join-Path -Path $GetFolder.FullName -ChildPath "\bin\ffmpeg.exe"
                Copy-Item -Path $FFMPEGLocation -Destination $ExeFile

                Write-Host "Latest version of FFMPEG executable successfully downloaded." -ForegroundColor "Green"

            } Catch {
                $ErrorMessage = $_.Exception.Message
                Write-Verbose $ErrorMessage
                Write-Host "There was an error while attempting to download and unzip the zip file. Please manually download the file and place ffmpeg in $scriptPath"
            }

            Write-PauseMessage "Press a key to continue..."
            Show-FFMPEGUtilities
        }
        3 {  }
    }

    Clear-Host
    Get-OnlineVersion
    Show-Menu
}

Function Show-Help {

    Clear-Host
    Write-Host ""
    Write-HostCenter "-------------------------------------------------------" -Colour Yellow
    Write-HostCenter "Help Menu" -Colour Yellow
    Write-HostCenter "-------------------------------------------------------" -Colour Yellow
    Write-Host ""
    Write-HostCenter "Welcome to the Scan Media help screen."
    Write-Host ""
    Write-Host (Write-WrapString "This script utilizes ffmpeg, the same tool Plex uses, to decode the video stream and captures the output for any errors during playback and sends the playback errors to a log file. So essentially it plays the video in the background faster than regular speed. It then checks the error output log file to see if there is anything inside. If ffmpeg was able to cleanly play the file, it counts as a passed file. If there is any error output, an error could be anything from a container issue, a missed frame issue, media corruption or more, it counts the file as failed. So if there would be an issue with playback and a video freezing, it would be caught by this method of checking for errors. Because of the nature of the error log, any errors that show up, even simple ones, will all count as a fail and the output is captured so you can view the error log. Some simple errors are easy to fix so I have included an auto-repair feature which attempts to re-encode the file which is able to correct some issues that would cause problems during playback. It can attempt a repair and delete the original if the new file scans successfully, as an option. " )
    Write-Host ""
    Write-Host (Write-WrapString "This script can be used to scan on or more video files by targeting a single file or a directory that contains multiple files or folders. While running any powershell script, you can stop it at any time by pushing Ctrl + C.")
    Write-Host ""
    Write-Host "You can get further explanations with the following help menus:" -ForegroundColor Yellow
    Write-Host " 1:  Main Menu Help"
    Write-Host " 2:  Command line Parameter and Script Options Help"
    Write-Host " 3:  Main Menu"
    Write-Host ""
    Write-Host "Please make a selection from the Menu Choices." -ForegroundColor Cyan 

    $MenuChoice = 0
    while ($MenuChoice -lt 1 -or $MenuChoice -gt 3) {
        Write-Host "Choice Number: " -ForegroundColor Cyan -NoNewline
        $MenuChoice = Read-Host
    }

    switch ($MenuChoice) {
        1 {  
            Clear-Host
            Write-Host ""
            Write-HostCenter "-------------------------------------------------------" -Colour Yellow
            Write-HostCenter "Main Menu Help" -Colour Yellow
            Write-HostCenter "-------------------------------------------------------" -Colour Yellow
            Write-Host ""
            Write-Host (Write-WrapString "The main menu consists of three scan options, the ability to generate a configuration file and FFMPEG utilities. The three scan options are designed to allow you to quickly get started scanning without the use of command line or configurations. Command line arguments or a configuration file will allow you have more control over scanning and bypass the menu completely." )
            Write-Host ""
            Write-Host "Here are the menu options and a description of their use:"
            $HelpItems = New-Object System.Collections.ArrayList
            $HelpItemBlank = New-Object PSObject -Property @{MenuItem="";HelpText=""}
            $HelpItem = New-Object PSObject -Property @{MenuItem="Quick Scan";HelpText="This scan option provides a quick ability to initiate a scan on a directory or file without getting some more advanced options provided with this script. Auto-Rescan is automatically enabled to provided users a fast and easy experience with scanning all of files targeted."}
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null
            $HelpItem = New-Object PSObject -Property @{MenuItem="Default Scan";HelpText="This scan option provides the regular scan ability like Quick Scan but also exposes more options to change the scanner abilities. Unlike Quick Scan where re-scan enabled, you are asked if you would like to enable it. The following options can be configured for this scan: Re-Scan of items already scanned, LimitCPU if enabled limits the amount of CPU usage, Auto-Repair that when enabled attempts to repair files by re-encoding them to correct some errors, deletion options that allow for the deletion of bad repaired files, bad original files, or both, and the TrashEnabled which will allow you to move files found to have an error into a single directory."}
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null
            $HelpItem = New-Object PSObject -Property @{MenuItem="Background Scan";HelpText="This scan option is designed to allow for a long scan duration or a continuous scan without massively interrupting other resources on the same machine. A CPU limit is automatically enabled for this scan. The following options can be configured for this scan: Idle Scan prevents the scanner from running if CPU usage on the machine is above 25%, Re-Scan of items already scanned, deletion options that allow for the deletion of bad repaired files, bad original files, or both, Continuous scan which will automatically start another scan in 15 minutes once a scan has completed, and the TrashEnabled which will allow you to move files found to have an error into a single directory."}
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null
            $HelpItem = New-Object PSObject -Property @{MenuItem="Create a Configuration file";HelpText="This allows for the creation of a JSON settings file that can be used in conjunction with the command line parameter -ConfigFile. A series of questions will be asked about the type of scan you would like to run and then a file will be saved. If a configuration file is supplied at command line, no menu will be shown. This can be used to setup an automated scanning process with a program like Task Scheduler."}
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null
            $HelpItem = New-Object PSObject -Property @{MenuItem="FFMPEG Utilities";HelpText="The option allows you to verify that the ffmpeg.exe file required by the script is configured correctly. If ffmpeg.exe is not found there is an option to download the latest version and place it into the proper location. Once downloaded you can validate that the script can access the ffmpeg.exe before proceeding to scan."}
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null

            $HelpItems | Select-Object -Property MenuItem,HelpText | Format-Table -AutoSize -Wrap -HideTableHeaders

            Write-PauseMessage "Push any key to continue..."
            Show-Help
        }
        2 {
            Clear-Host
            Write-Host ""
            Write-HostCenter "-------------------------------------------------------" -Colour Yellow
            Write-HostCenter "Command line Parameter and Script Options Help" -Colour Yellow
            Write-HostCenter "-------------------------------------------------------" -Colour Yellow
            Write-Host ""
            Write-Host (Write-WrapString "This help section will go over all of the available command line arguments with a description of their functionality and examples. All script functionality can be accessed through the command line and the script menu system can be bypassed allowing for another method for automation." )
            Write-Host "Command line parameters can be used at the same time as calling the script as seen in the example below example:"
            Write-Host ""
            Write-Host '.\ScanMedia.ps1 -Path "C:\Media\Videos" -LimitCPU -AutoRepair -RemoveOriginal -RemoveRepaired -BypassMenu'
            Write-Host ""
            Write-Host (Write-WrapString "This example bypasses the menu and scans the path C:\Media\Videos with lower CPU usage and attempts to repair the files that are found to have an issue. The script will delete repaired files that don't repair properly and it will delete the original files of successfully repaired files.")
            Write-Host ""
            Write-Host "Here is a list of parameters/options with an overview of their use:"
            $HelpItems = New-Object System.Collections.ArrayList
            $HelpItemBlank = New-Object PSObject -Property @{MenuItem="";HelpText=""}
            $HelpItem = New-Object PSObject -Property @{MenuItem="Path";HelpText='This is the folder or file that the script will begin recursively scanning with FFMPEG. If running this script as administrator, you typically want to provide the full network path instead of a drive letter. Calling Syntax: -Path "C:\Media\Videos" or -Path "\\SEVERVERSHARE\Media\Videos"'}
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null
            $HelpItem = New-Object PSObject -Property @{MenuItem="AutoRepair";HelpText="When supplied, the script will automatically attempt to repair any file that is found to have issues. Only a certain number of issues will be able to be corrected with this method and it will not be possible to repair all files. After a video is repaired, it is then scanned to check to make sure the repair was successful and verifies that the runtime matches that of the original file. Bad auto-repaired files can be automatically removed with the use of -RemovedRepaired. Calling Syntax: -AutoRepair"}
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null
            $HelpItem = New-Object PSObject -Property @{MenuItem="Rescan";HelpText="When supplied, forces the script to ignore the Scan History File and will re-scan of all files in the path supplied. Calling Syntax: -Rescan"}
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null
            $HelpItem = New-Object PSObject -Property @{MenuItem="ContinuousScan";HelpText="When supplied, once a scan completes a new scan will be kicked off in 15 minutes with the same parameters as the last scan. This can be used to setup automatic scanning on a directory for any new files, if previous files are ignored. Calling Syntax: -ContinuousScan"}
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null
            $HelpItem = New-Object PSObject -Property @{MenuItem="CRF";HelpText="Stands for Constant Rate Factor, can be within the range of 0 - 51, where 0 is lossless and 51 is the worst quality possible. 21 is the default value for this script. A lower value generally leads to higher quality, and a subjectively same range is 17 - 28. Consider 17 or 18 to be visually lossless or nearly so; it should look the same or nearly the same as the input but it isn't technically lossless. The range is exponential, so increasing the CRF value +6 results in roughly half the bitrate / file size, while -6 leads to roughly twice the bitrate.  Calling Syntax: -CRF 25"}  
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null
            $HelpItem = New-Object PSObject -Property @{MenuItem="LimitCPU";HelpText="When supplied, the script will attempt to run FFMPEG with half of the available cores assigned to the current system. If 4 cores are available, FFMPEG will utilize 2. If 1 core is available to the system, this parameter will have no affect. Scan and repair time will increase with this parameter. Calling Syntax: -LimitCPU"} 
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null
            $HelpItem = New-Object PSObject -Property @{MenuItem="IdleScan";HelpText="When supplied, stops a scan from being initiated unless CPU usage is below 25%. This will stop the script from competing for resources if the machine is in use with other tasks. Once the CPU is idle a scan will continue. Calling Syntax: -IdleScan"} 
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null
            $HelpItem = New-Object PSObject -Property @{MenuItem="RemoveRepaired";HelpText="When supplied, the script will DELETE all of the repaired files that did not scan as successfully repaired. Calling Syntax: -RemoveRepaired"} 
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null
            $HelpItem = New-Object PSObject -Property @{MenuItem="RemoveOriginal";HelpText="When supplied, the script will DELETE the original video file if it was repaired successfully. It will then overwrite the original file name with the name of the successfully repaired file. It will not remove original files unless a repair was attempted and it was successful. All other original files will be un-touched. It is recommended to only run this command if a backup is in place for the media being scanned. If -IAcceptResponsibility is not supplied at run time, the script will prompt the user to type IACCEPT during runtime. Calling Syntax: -RemoveOriginal"} 
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null
            $HelpItem = New-Object PSObject -Property @{MenuItem="RemoveAll";HelpText="When supplied, will DELETE all of the files that are found to have errors and is not dependant of if they are able to be successfully repaired. It is recommended to only run this command if a backup is in place for the media being scanned. If -IAcceptResponsibility is not supplied at run time, the script will prompt the user to type IACCEPT during runtime. Calling Syntax: -RemoveAll"} 
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null
            $HelpItem = New-Object PSObject -Property @{MenuItem="IAcceptResponsibility";HelpText="When supplied, the user accepts responsibility when supplying parameters that will potentially delete original files. This should only be used when you understand the risks involved. Calling Syntax: -IAcceptResponsibility"} 
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null
            $HelpItem = New-Object PSObject -Property @{MenuItem="ConfigFile";HelpText='When supplied, the script will load the configuration saved in the supplied JSON file and initiate a scan with those values. This will allow you to save a popular scan with the settings you require and then call the script with the configuration file for automatic scanning. This could be used in conjunction with scheduling software to setup an automated method to monitor directories. Calling Syntax: -ConfigFile "C:\ScanFiles\ScanConfig-2020-11-30.json" '} 
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null
            $HelpItem = New-Object PSObject -Property @{MenuItem="BypassMenu";HelpText="When supplied, the starting interactive menu will be bypassed so that no user interaction is required to initiate a scan. If calling the script using command line arguments where no user interaction is wanted, supply this parameter to ensure there is no interruptions when starting a scan. Not required when using the parameter -ConfigFile. The -path parameter is required for no user interaction. Calling Syntax: -BypassMenu "} 
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null
            $HelpItem = New-Object PSObject -Property @{MenuItem="GPUEncoding";HelpText="When supplied, ffmpeg with utilize the GPU to encode files, lowering CPU usage, by changing the encoding library being used to h264_nvenc. Note: This requires both your GPU and the ffmpeg binary to support GPU encoding. This will not work with the default ffmpeg binary file. To utilize this feature you need to find out what is required for GPU encoding through ffmpeg. Calling Syntax: -GPUEncoding "} 
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null
            $HelpItem = New-Object PSObject -Property @{MenuItem="Extension";HelpText='When supplied, will change the extension of files repaired with ffmpeg. To be used in conjunction with -GPUEncoding or else the default of .mp4 will be compatible with the default encoding library. Calling Syntax: -Extension ".mkv" '} 
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null
            $HelpItem = New-Object PSObject -Property @{MenuItem="TrashEnabled";HelpText='When supplied, will move all files found with issues will be moved to the folder specified for remediation. This option will take priority over -RemoveAll or -RemoveOriginal if both are called. Calling Syntax: -TrashEnabled "X:\Media\BadFiles"'} 
            $HelpItems.Add($HelpItem) | Out-Null
            $HelpItems.Add($HelpItemBlank) | Out-Null

            $HelpItems | Select-Object -Property MenuItem,HelpText | Format-Table -AutoSize -Wrap -HideTableHeaders

            Write-PauseMessage "Push any key to continue..."
            Show-Help
         }
        3 {

         }
    }

    Clear-Host
    Get-OnlineVersion
    Show-Menu
}

Function Update-VideoArray {
    Param (
        [String]$Status,
        [Object]$VideoFile,
        [Switch]$Update)

    If ($global:VideoList.Length -eq 500) {
        $global:VideoList.RemoveAt(0)
    }
    If ($Update) {
        $MediaFile = New-Object PSObject -Property @{Name=$VideoFile.Name;Path=$VideoFile.DirectoryName;Status=$Status;FullName=$VideoFile.FullName}

        $ScanList = $global:VideoList | Where-Object { ($_.FullName -eq $VideoFile.FullName) }
        If ($ScanList) {
            Foreach ($file in $ScanList) {
                $global:VideoList.Remove($file)
            }
        }
        $global:VideoList.Add($MediaFile) | Out-Null
    } Else {
        $MediaFile = New-Object PSObject -Property @{Name=$VideoFile.Name;Path=$VideoFile.DirectoryName;Status=$Status;FullName=$VideoFile.FullName}
        $global:VideoList.Add($MediaFile) | Out-Null
    }
}

Function Write-ScanOutput {
    Param (
        [switch]$Scanning,
        [switch]$Repairing
    )

    Clear-Host

    # Check if script is running in PowerShell ISE which does not expose console size
    If ($Host.UI.SupportsVirtualTerminal) {
        $Width = (Get-Host).UI.RawUI.WindowSize.Width
        $Height = (Get-Host).UI.RawUI.WindowSize.Height
    } Else {
        $Width = (Get-Host).UI.RawUI.BufferSize.Width
        $Height = 50
    }

    $OutputPath = $global:Path.subString(0, [System.Math]::Min(($Width - 20), $global:Path.Length))

    If ($global:Path.Length -gt ($Width - 20)) {
        $OutputPath = $OutputPath + "..."
    }

    Write-Host ""
    Write-HostCenter "##################################################################################################################" -Colour Cyan
    Write-HostCenter "Scanning $OutputPath" -Colour Cyan
    Write-HostCenter "##################################################################################################################" -Colour Cyan
    Write-Host ""

    If ($global:AutoRepair) {
        Write-HostCenter "Files Scanned: $($global:VideoCount) | Errors Found: $($global:ErrorList.Count) | Repair Errors: $($global:RepairedErrorList.Count)"
    } Else {
        Write-HostCenter "Files Scanned: $($global:VideoCount) | Errors Found: $($global:ErrorList.Count)"
    }

    $global:VideoList | Select-Object -Property Name,Status,Path | Select-Object -Last ($Height - 13) | Format-Table -AutoSize | Out-String -Stream | ForEach-Object {
        If ($_.Contains(" Skipped ")) {
            Write-Host $_ -ForegroundColor Gray
        } ElseIf ($_.Contains(" Passed ")) {
            Write-Host $_ -ForegroundColor Green
        } ElseIf ($_.Contains(" Failed ")) {
            Write-Host $_ -ForegroundColor Red
        } ElseIf ($_.Contains(" Deleted ")) {
            Write-Host $_ -ForegroundColor Yellow
        } ElseIf ($_.Contains(" Passed:Renamed ")) {
            Write-Host $_ -ForegroundColor Green
        } ElseIf ($_.Contains(" Moved ")) {
            Write-Host $_ -ForegroundColor Yellow
        } Else {
            Write-Host $_
        }
    }

    If ($Scanning) {
        Write-HostCenter "Please wait, Scan in progress..."
    }
    If ($Repairing) {
        Write-HostCenter "Please wait, Repair in progress..."
    }
}

Function Write-WrapString {
    Param (
        [String]$str
    )

    # Check if script is running in PowerShell ISE which does not expose console size
    If ($Host.UI.SupportsVirtualTerminal) {
        $Width = (Get-Host).UI.RawUI.WindowSize.Width
    } Else {
        $Width = (Get-Host).UI.RawUI.BufferSize.Width
    }

	# Holds the final version of $str with newlines
	$strWithNewLines = ""
	# current line, never contains more than screen width
	$curLine = ""
	# Loop over the words and write a line out just short of window size
	foreach ($word in $str.Split(" "))
	{
		# Lets see if adding a word makes our string longer then window width
		$checkLinePlusWord = $curLine + " " + $word
		if ($checkLinePlusWord.length -gt $Width)
		{
			# With the new word we've gone over width
			# append newline before we append new word
			$strWithNewLines += [Environment]::Newline
			# Reset current line
			$curLine = ""
		}
		# Append word to current line and final str
		$curLine += $word + " "
		$strWithNewLines += $word + " "
	}
	# return our word wrapped string
	return $strWithNewLines
}

Function New-MediaScan {
    # Test to see if the log directory exists and create it if not
    If (!(test-Path $LogDir)) {
        New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    }

    If (!(test-Path $LogPath)) {
        New-Item -ItemType Directory -Force -Path $LogPath | Out-Null
    }

    If ($global:RemoveAll -or $global:RemoveOriginal) {
        If (!($global:IAcceptResponsibility)) {
            $Acceptance = ""

            LogWrite "************************* WARNING *******************************" -Colour "Red"
            LogWrite "The commands supplied have the ability to delete original files" -Colour "Yellow"
            LogWrite "A backup is highly recommended when supplying these commands" -Colour "Yellow"
            LogWrite "Please type the following confirm you understand: IACCEPT" -Colour "Yellow"
            LogWrite "************************* WARNING *******************************" -Colour "Red"

            while ($Acceptance -ne "IACCEPT") {
                Write-Host "Please Type the above command: " -ForegroundColor Magenta -NoNewline
                $Acceptance = Read-Host
            }
        }
    }

    LogWrite "Starting script $($MyInvocation.MyCommand.Name)" -Log

    # Test the CSV file path and create the CSV with the header line if it does not exist
    If (!(test-Path $CSVfile)) {
        Set-Content $CSVfile -Value "File Name,FFMPEG Test,Check Date,File Size (MB),Video Length,Location"
    }

    If (!(test-Path $scanHistory)) {
        Set-Content $scanHistory -Value "This is a history of all scanned items. Please do not delete or modify this file."
        LogWrite "Creating a history file: $scanHistory "
        LogWrite "Please do not remove this file if you would like to keep a history of scanned items."
    }

    If ($global:AutoRepair) {
        LogWrite "Auto-Repair has been enabled" -Colour "Cyan"
    }

    If ($global:Rescan) {
        LogWrite "Media Rescan has been enabled. All files will be scanned." -Colour "Cyan"
    }

    If ($global:RemoveRepaired) {
        LogWrite "WARNING: Auto-Delete has been enabled for repaired files. All repaired files that have errors will be automatically removed" -Colour "Yellow"
    }

    If ($global:RemoveAll) {
        LogWrite "WARNING: Auto-Delete has been enabled for all files. All files that have errors will be automatically removed" -Colour "Yellow"
    }

    If ($global:RemoveOriginal) {
        LogWrite "WARNING: Auto-Delete has been enabled for original files. All original files that have errors will be automatically removed after a repair has completed successfully" -Colour "Yellow"
    }

    If ($global:IAcceptResponsibility) {
        LogWrite "You have acknowledged that original files will potentially be removed when using RemoveAll or RemoveOriginal and supplying -IAcceptResponsibility" -Colour "Magenta"
    }

    If ($global:LimitCPU) {
        LogWrite "Determining the number of CPUs to utilize for lower CPU usage." -Colour "Cyan"
        $global:CPULimt = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors / 2
        If ($global:CPULimt -lt 1) {
            $global:CPULimt = 1
        }
        LogWrite "Limiting the CPU usage for FFMPEG to $global:CPULimt core(s)" -Colour "Cyan"
    }

    If ($global:IdleScan) {
        LogWrite "IdleScan has been enabled. A file will only be scanned if CPU usage is below 25 percent" -Colour "Cyan"
    }

    If ($global:GPUEncoding) {
        LogWrite "GPU Encoding has been enabled. This requires that FFMPEG and your GPU both support GPU encoding. This should only be enabled if you have verified functionality." -Colour "Cyan"
        $global:VideoLibrary = "h264_nvenc"
    }

    If ($global:ContinuousScan) {
        LogWrite "Continuous Scanning has been enabled. 15 minutes after a scan is completed a new scan will be started using the same values as the pervious scan" -Colour "Cyan"
    }

    If ($global:TrashEnabled) {
        LogWrite "Trash has been enabled. Video files with errors found will be moved to the folder: $global:TrashEnabled" -Colour "Cyan"
    }

    # Check to see if ffmpeg exists and if it is installed on the local machine and added to path
    If ($null -eq (Get-Command "ffmpeg.exe" -ErrorAction SilentlyContinue)) { 
        LogWrite "ERROR: Unable to find ffmpeg.exe on the computer or in the local script directory" -Colour "Red"
        LogWrite "Please download ffmpeg and place ffmpeg.exe in: $scriptPath or use the downloader in the FFMPEG Utilities Menu" -Colour "Cyan"
        LogWrite "Exiting Script" -Colour "Red"
        Exit
    }

    # Check to make sure the path supplied to scan exists for the current user
    If (!(Test-Path -LiteralPath $global:Path)) {
        LogWrite "ERROR: Unable to access the directory: $global:Path" -Colour "Red"
        If (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            LogWrite "Running as administrator is not required and can cause issues accessing network folders that have been mapped. Please supply the direct share path I.E. \\SERVER\SHARE\PATH"
        }
        LogWrite "Exiting Script" -Colour "Red"
        Exit
    }

    Write-Verbose "Path: $global:Path"
    Write-Verbose "LogDir: $global:LogDir"
    Write-Verbose "ConfigFile: $global:ConfigFile"
    Write-Verbose "AutoRepair: $global:AutoRepair"
    Write-Verbose "Rescan: $global:Rescan"
    Write-Verbose "CRF: $global:CRF"
    Write-Verbose "LimitCPU: $global:LimitCPU"
    Write-Verbose "CPULimt: $global:CPULimt"
    Write-Verbose "RemoveAll: $global:RemoveAll"
    Write-Verbose "RemoveRepaired: $global:RemoveRepaired"
    Write-Verbose "RemoveOriginal: $global:RemoveOriginal"
    Write-Verbose "IAcceptResponsibility: $global:IAcceptResponsibility"
    Write-Verbose "IdleScan: $global:IdleScan"
    Write-Verbose "GPUEncoding: $global:GPUEncoding"
    Write-Verbose "VideoLibrary: $global:VideoLibrary"
    Write-Verbose "RepairVFileExtension: $global:RepairVFileExtension"
    Write-Verbose "ContinuousScan: $global:ContinuousScan"
    Write-Verbose "TrashEnabled: $global:TrashEnabled"
    
    If ((!($global:ConfigFile)) -and (!($BypassMenu))) {
        Write-PauseMessage "Ready to begin scan on $global:Path Press any key to continue..."
    }

    Clear-Host
    $ContinuousScan = $true

    While ($ContinuousScan) {

        $global:VideoList = New-Object System.Collections.ArrayList
        $global:VideoList.Capacity = 500
        $global:ErrorList = New-Object System.Collections.ArrayList
        $global:RepairedErrorList = New-Object System.Collections.ArrayList
        $global:VideoCount = 0
        $global:SkipCount = 0

        switch ($true) {
            $IsWindows { 
                <# PowerShell 6+ #> 
                LogWrite "Running on a Windows Machine with PowerShell version 6+" -Log
            }
            $IsMacOS { 
                LogWrite "Running on a Mac OS with PowerShell CORE" -Log
            }
            $IsLinux { 
                LogWrite "Running on a Linux OS with PowerShell CORE" -Log
            }
            Default { 
                <# Windows PowerShell #>
                LogWrite "Running on a Windows Machine with PowerShell version below 6" -Log
            }
        }

        $Timer = [system.diagnostics.stopwatch]::StartNew()

        LogWrite "" -Log
        LogWrite "##################################################################################################################" -Log
        LogWrite "Beginning Scan on $global:Path" -Log
        LogWrite "##################################################################################################################" -Log
        LogWrite "" -Log

        Write-ScanOutput

        # Get all the child items of the supplied directory and attempt to scan the files with the function CheckFile
        Get-ChildItem -LiteralPath $global:Path -File -Recurse | Where-Object { $include -contains $_.Extension } | ForEach-Object {

            If ($global:IdleScan) {
                $CPUAverage = Get-WmiObject Win32_Processor | Measure-Object -Property LoadPercentage -Average | Select-Object Average
                While ($CPUAverage.Average -gt 25) {
                    Write-Verbose "CPU usage above 25 percent. Pausing for 5 minutes"
                    Write-Verbose "Current CPU Usage: $($CPUAverage.Average)"
                    Start-Sleep -s 300
                    $CPUAverage = Get-WmiObject Win32_Processor | Measure-Object -Property LoadPercentage -Average | Select-Object Average
                }
            }

            # Check the scan history file to see if the file has been scanned
            $scanHistoryCheck = (Get-Content $scanHistory | Select-String -pattern $_.FullName -SimpleMatch)

            # If the file exists in the scan history and Rescan has not been enabled, skip
            If (($null -ne $scanHistoryCheck) -and ($global:Rescan -eq $false)) {
                Update-VideoArray -VideoFile $_ -Status "Skipped"
                LogWrite "Skipping scanned file: $($_.Name)" -Log
                $global:SkipCount = $global:SkipCount + 1
                Write-ScanOutput
            }
            # If the file exists in the scan history and Rescan has been  enabled, scan the file
            Elseif (($null -ne $scanHistoryCheck) -and ($global:Rescan -eq $true)) {
                CheckFile $_ -RescanVideo
            } 
            Else {
                CheckFile $_ 
            }
        }

        Write-ScanOutput
        $TimeSpan = New-TimeSpan -Seconds $Timer.Elapsed.TotalSeconds
        $Elapsed = '{0:000}h:{1:00}m:{2:00}s' -f $TimeSpan.Hours,$TimeSpan.Minutes,$TimeSpan.Seconds
        $Timer.Stop()
        LogWrite "Number of Files Scanned: $global:VideoCount"
        LogWrite "Elapsed Time: $($Elapsed)"
        LogWrite "Scan Log file: $Logfile"
        If ($global:ErrorList.Count -gt 0) {
            LogWrite "Number of files that were found with an error: $($global:ErrorList.Count)" -Colour Yellow
            LogWrite "Printing out filename(s) with errors into the log file"
            foreach ($file in $global:ErrorList) {
                LogWrite "$file" -Log
            }
        }
        If ($global:RepairedErrorList.Count -gt 0) {
            LogWrite "Number of repaired files that were found with an error: $($global:RepairedErrorList.Count)" -Colour Yellow
        }
        If ($global:SkipCount -gt 0) {
            LogWrite "Number of files skipped: $($global:SkipCount)"
        }

        If (!($global:ContinuousScan)) {
            $ContinuousScan = $false
            LogWrite "Scan Complete."
            If ((!($BypassMenu)) -or (!($global:ConfigFile))) {
                Write-PauseMessage "Push any key to quit the script..."
            }
        } Else {
            LogWrite "Starting new scan in 15 minutes"
            Start-Sleep -Seconds 900
        }
    }
}

Clear-Host

If ($scriptPath.Contains("[") -or $scriptPath.Contains("]")) {
    Write-Host "ERROR: Invalid Script Path. Due to how Powershell handles [] characters. Please run the script from a path that does not contain [ or ]." -ForegroundColor Yellow
    Write-Error "ERROR: Invalid Script Path. Due to how Powershell handles [] characters. Please run the script from a path that does not contain [ or ]."
    Exit 1
}

# Change the location of the working directory to where the script is launched from
Set-Location -Path $scriptPath

If ((!$global:ConfigFile) -and (!$BypassMenu)) {
    Write-Host ""
    Write-Host ""
    Write-HostCenter "##################################################################################################################" -Colour Cyan
    Write-HostCenter "Scan Media PowerShell Script" -Colour Cyan
    Write-HostCenter "##################################################################################################################" -Colour Cyan
    Write-Host ""
    Write-Host ""
    Write-Host "$(Get-Date) Initializing ScanMedia Script"
    Write-Host "$(Get-Date) Script Version: $ScriptVersion"
    Write-Host "$(Get-Date) Program's GitHub: https://gist.github.com/Desani/129be27da7d735d7c75192ec1aa96c65"
    Get-OnlineVersion
    Show-Menu
} Else {
    If ($global:ConfigFile) {
        # Convert JSON Values to the Global Variables
        Try {
            $JSON = Get-Content $ConfigFile | Out-String | ConvertFrom-Json
        } Catch {
            $ErrorMessage = $_.Exception.Message
            Write-Error "Error. There was an issue reading from the JSON file."
            Write-Host $ErrorMessage
            Exit 1
        }

        $PathHash = $JSON | Where-Object { ($_.Name -eq "Path") }
        $global:Path = $PathHash.Value

        $LogDirHash = $JSON | Where-Object { ($_.Name -eq "LogDir") }
        $global:LogDir = $LogDirHash.Value

        $LogPath = Join-Path -path $global:LogDir -childpath "Log_$Date"
        $ffmpegLog = Join-Path -path $LogPath -childpath "ffmpegerror.log"
        $Logfile = Join-Path -path $LogPath -childpath "results.log"
        $CSVfile = Join-Path -path $LogPath -childpath "results.csv"

        $IdleScanHash = $JSON | Where-Object { ($_.Name -eq "IdleScan") }
        $global:IdleScan = $IdleScanHash.Value

        $LimitCPUHash = $JSON | Where-Object { ($_.Name -eq "LimitCPU") }
        $global:LimitCPU = $LimitCPUHash.Value

        $RescanHash = $JSON | Where-Object { ($_.Name -eq "Rescan") }
        $global:Rescan = $RescanHash.Value

        $AutoRepairHash = $JSON | Where-Object { ($_.Name -eq "AutoRepair") }
        $global:AutoRepair = $AutoRepairHash.Value

        $CRFHash = $JSON | Where-Object { ($_.Name -eq "CRF") }
        $global:CRF = $CRFHash.Value

        $RemoveRepairedHash = $JSON | Where-Object { ($_.Name -eq "RemoveRepaired") }
        $global:RemoveRepaired = $RemoveRepairedHash.Value

        $RemoveOriginalHash = $JSON | Where-Object { ($_.Name -eq "RemoveOriginal") }
        $global:RemoveOriginal = $RemoveOriginalHash.Value

        $RemoveAllHash = $JSON | Where-Object { ($_.Name -eq "RemoveAll") }
        $global:RemoveAll = $RemoveAllHash.Value

        $ContinuousScanHash = $JSON | Where-Object { ($_.Name -eq "ContinuousScan") }
        $global:ContinuousScan = $ContinuousScanHash.Value

        $TrashEnabledHash = $JSON | Where-Object { ($_.Name -eq "TrashEnabled") }
        If ($TrashEnabledHash) {
            $global:TrashEnabled = $TrashEnabledHash.Value
        }

        $global:IAcceptResponsibility = $true

        New-MediaScan
    } ElseIf ($BypassMenu) {
        Get-MediaPath -ScanType "Custom"
        New-MediaScan
    }
}