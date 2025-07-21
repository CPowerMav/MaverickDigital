@echo off
setlocal enabledelayedexpansion

REM Remove duplicate frames from video
REM Usage: remove_duplicates.bat input_video.mp4 [output_video.mp4]

set INPUT_FILE=%~1
if "%INPUT_FILE%"=="" (
    echo Usage: %~nx0 input_video.mp4 [output_video.mp4]
    exit /b 1
)

if not exist "%INPUT_FILE%" (
    echo Error: Input file '%INPUT_FILE%' not found!
    exit /b 1
)

REM Set output file name
if "%~2"=="" (
    set OUTPUT_FILE=%~n1_no_duplicates.mov
) else (
    set OUTPUT_FILE=%~2
)

echo Processing: %INPUT_FILE%
echo Output: %OUTPUT_FILE%

REM Get original frame rate
for /f "tokens=*" %%i in ('ffprobe -v quiet -select_streams v:0 -show_entries stream^=r_frame_rate -of csv^=s^=x:p^=0 "%INPUT_FILE%"') do set ORIGINAL_FPS=%%i

echo Original FPS: %ORIGINAL_FPS%

REM Remove duplicates and encode to ProRes 422
ffmpeg -i "%INPUT_FILE%" -vf "mpdecimate=hi=200:lo=200:frac=1:max=0,setpts=N/FRAME_RATE/TB" -r %ORIGINAL_FPS% -c:v prores -profile:v 2 -c:a pcm_s16le "%OUTPUT_FILE%"

echo Done! Output saved as: %OUTPUT_FILE%