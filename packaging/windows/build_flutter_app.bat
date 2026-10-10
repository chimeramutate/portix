@echo off
REM Build Flutter Windows App (without rebuilding Rust libraries)
REM Usage: build_flutter_app.bat [version]

setlocal enabledelayedexpansion

REM Get version
set VERSION=%1
if "%VERSION%"=="" set VERSION=dev

echo.
echo === Building Portix Flutter Windows App ===
echo Version: %VERSION%
echo.

REM Get project root
set SCRIPT_DIR=%~dp0
for %%D in ("%SCRIPT_DIR%..\..") do set PROJECT_ROOT=%%~fD
set PORTIX_APP=%PROJECT_ROOT%\portix_app

REM Check if Rust libraries exist
echo Checking Rust libraries...
if not exist "%PORTIX_APP%\artifacts\portix_serv.dll" (
    echo Error: portix_serv.dll not found in %PORTIX_APP%\artifacts
    echo Build Rust libraries first or download from CI artifact
    exit /b 1
)

if not exist "%PORTIX_APP%\artifacts\portix_rdp.dll" (
    echo Error: portix_rdp.dll not found in %PORTIX_APP%\artifacts
    echo Build Rust libraries first or download from CI artifact
    exit /b 1
)

echo Rust libraries found.

REM Clean previous build
echo Cleaning previous Flutter build...
if exist "%PORTIX_APP%\build\windows" rmdir /s /q "%PORTIX_APP%\build\windows"

REM Build Flutter Windows
echo Building Flutter Windows...
cd /d "%PORTIX_APP%"
flutter build windows --release --build-name=%VERSION% --build-number=1

REM Check if build succeeded
set BUILD_OUTPUT=%PORTIX_APP%\build\windows\runner\Release
if not exist "%BUILD_OUTPUT%" (
    echo Error: Build output not found
    exit /b 1
)

REM Copy DLLs to Release folder
echo Bundling Rust libraries...
copy /y "%PORTIX_APP%\artifacts\portix_serv.dll" "%BUILD_OUTPUT%\"
copy /y "%PORTIX_APP%\artifacts\portix_rdp.dll" "%BUILD_OUTPUT%\"

REM Create output directory
set OUT_DIR=%PROJECT_ROOT%\dist\windows
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

REM Create zip
echo Creating ZIP...
cd "%OUT_DIR%"
powershell -command "Compress-Archive -Path ..\..\..\portix_app\build\windows\runner\Release\* -DestinationPath 'portix-%VERSION%-win.zip' -Force"

echo.
echo === Build Complete ===
echo Output: %OUT_DIR%\portix-%VERSION%-win.zip
echo.

endlocal