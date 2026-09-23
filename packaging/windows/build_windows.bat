@echo off
REM Build Windows EXE for Portix
REM Usage: build_windows.bat [version] [build_number]

setlocal enabledelayedexpansion

REM Default values
set VERSION=%1
if "%VERSION%"=="" set VERSION=1.0.0
set BUILD_NUMBER=%2
if "%BUILD_NUMBER%"=="" set BUILD_NUMBER=1

echo.
echo === Building Portix Windows EXE ===
echo Version: %VERSION%
echo Build Number: %BUILD_NUMBER%
echo.

REM Colors (using Windows 10+)
set "GREEN=[32m"
set "YELLOW=[33m"
set "RED=[31m"
set "NC=[0m"

REM Get project root
set SCRIPT_DIR=%~dp0
for %%D in ("%SCRIPT_DIR%..\..") do set PROJECT_ROOT=%%~fD

set PORTIX_APP=%PROJECT_ROOT%\portix_app
set DIST_DIR=%PROJECT_ROOT%\dist
set OUT_DIR=%DIST_DIR%\windows

echo %YELLOW%Cleaning previous builds...%NC%
if exist "%OUT_DIR%" rmdir /s /q "%OUT_DIR%"
mkdir "%OUT_DIR%"

REM Build SSH library
echo %YELLOW%Building SSH library for Windows...%NC%
cd /d "%PROJECT_ROOT%\portix_serv"
cargo build --release
if exist "target\release\portix_serv.dll" (
    copy /y "target\release\portix_serv.dll" "%PORTIX_APP%\artifacts\"
) else if exist "target\release\libportix_serv.dll" (
    copy /y "target\release\libportix_serv.dll" "%PORTIX_APP%\artifacts\"
)
echo %GREEN%SSH library built%NC%

REM Build RDP library
echo %YELLOW%Building RDP library for Windows...%NC%
cd /d "%PROJECT_ROOT%\portix_rdp"
cargo build --release
if exist "target\release\portix_rdp.dll" (
    copy /y "target\release\portix_rdp.dll" "%PORTIX_APP%\artifacts\"
) else if exist "target\release\libportix_rdp.dll" (
    copy /y "target\release\libportix_rdp.dll" "%PORTIX_APP%\artifacts\"
)
echo %GREEN%RDP library built%NC%

REM Build Flutter Windows app
echo %YELLOW%Building Flutter Windows app...%NC%
cd /d "%PORTIX_APP%"

flutter build windows --build-name=%VERSION% --build-number=%BUILD_NUMBER%

if errorlevel 1 (
    echo %RED%Flutter build failed!%NC%
    exit /b 1
)

echo %GREEN%Flutter Windows build completed%NC%

REM Package the output
echo %YELLOW%Packaging Windows output...%NC%

set BUILD_OUTPUT=%PORTIX_APP%\build\windows\runner\Release
if exist "%BUILD_OUTPUT%" (
    xcopy /s /e /i "%BUILD_OUTPUT%" "%OUT_DIR%\"
    
    REM Create archive
    cd "%OUT_DIR%"
    if exist "portix-%VERSION%-win-x64.zip" del "portix-%VERSION%-win-x64.zip"
    
    REM Use PowerShell for zip
    powershell -command "Compress-Archive -Path * -DestinationPath 'portix-%VERSION%-win-x64.zip' -Force"
    
    echo %GREEN%Windows package created: %OUT_DIR%\portix-%VERSION%-win-x64.zip%NC%
) else (
    echo %RED%Error: Build output not found. Check Flutter build logs.%NC%
    exit /b 1
)

REM Cleanup
cd /d "%PROJECT_ROOT%"

echo.
echo %GREEN%=== Windows Build Complete ===%NC%
echo Output: %OUT_DIR%\portix-%VERSION%-win-x64.zip
echo.

REM Generate checksums
cd /d "%OUT_DIR%"
powershell -command "Get-FileHash 'portix-%VERSION%-win-x64.zip' -Algorithm SHA256 | ForEach-Object { $_.Hash + '  portix-%VERSION%-win-x64.zip' } > 'portix-%VERSION%-win-x64.zip.sha256'"
echo %GREEN%Checksums generated%NC%

endlocal