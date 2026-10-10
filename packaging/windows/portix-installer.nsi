; Portix Installer Script
; Generated for NSIS (Nullsoft Scriptable Install System)
; 
; Build instructions:
;   1. Install NSIS from https://nsis.sourceforge.io/
;   2. Compile with: makensis portix-installer.nsi
;   3. Or use GUI: Right-click -> "Compile with NSIS"

!include "MUI2.nsh"
!include "LogicLib.nsh"

; ------------------------------
; General
; ------------------------------
!define PRODUCT_NAME "Portix"
!define PRODUCT_VERSION "1.0.0"
!define PRODUCT_PUBLISHER "Portix Team"
!define PRODUCT_WEB_SITE "https://github.com/portix/portix"
!define PRODUCT_DIR_REGKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Portix"
!define EXECUTABLE_TARGET "portix.exe"
!define UNINSTALL_EXECUTABLE_TARGET "uninstall.exe"

; ------------------------------
; Common
; ------------------------------
!define MUI_ABORTWARNING
!define MUI_AUTHUNINSTALL_REQUIRED
!define MUI_ICON "resources/installer-icons/mac-icon.icns"
!define MUI_UNICON "resources/installer-icons/mac-icon.icns"

; ------------------------------
; Logo/Branding
; ------------------------------
!define MUI_WELCOMEFILLPAGE "smooth"
!define MUI_INSTALLETRAYICON "portix.ico"
!define MUI_STARTMENU_IMAGE "portix.ico"
!define MUI_STARTMENU_IMAGE_POSTWIZARD "portix.ico"

; Brand colors
!define MUI_STYLEID 0x0002  ; Title bar color
!define MUI_SYSTEMCOLORS "highlight"

; ------------------------------
; Pages
; ------------------------------
!define MUI_PAGE_CUSTOMFIT_CREATE "@CustomFitCreate"
!define MUI_PAGE_CUSTOMFIT_LEAVE "@CustomFitLeave"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_STARTMENU Application $STARTMENU_FOLDER
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_WAITING
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; Progress bar info
!define MUI_INSTFILESPAGEFLAGS /SHOWCOMPLETED

; ------------------------------
; Address and Download Options
; ------------------------------
!define MUI_PAGE_CUSTOMSTRING_LEFT "Download: $INSTDIR"

; ------------------------------
; Shortcuts
; ------------------------------
Var StartMenuFolder

; ------------------------------
; Installer
; ------------------------------
Name "${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "Portix-${PRODUCT_VERSION}-Setup.exe"
InstallDir "$PROGRAMFILES64\Portix"
InstallDirRegKey $INSTDIR "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Portix"

; 32-bit and 64-bit support
!define DISABLEBit64

; ------------------------------
; Language
; ------------------------------
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "German"
!insertmacro MUI_LANGUAGE "French"
!insertmacro MUI_LANGUAGE "Spanish"
!insertmacro MUI_LANGUAGE "Japanese"
!insertmacro MUI_LANGUAGE "Chinese"

; ------------------------------
; Installer Sections
; ------------------------------
Section "Main Files" SecMain
  SetOutPath "$INSTDIR"
  
  ; Copy all files from build output
  File /r "Release\*.*"
  
  ; Create uninstaller
  WriteUninstaller "$INSTDIR\${UNINSTALL_EXECUTABLE_TARGET}"
  
  ; Register application
  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "UninstallString" '"$INSTDIR\${UNINSTALL_EXECUTABLE_TARGET}"'
  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "DisplayIcon" '"$INSTDIR\${EXECUTABLE_TARGET}"'
  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegDWORD SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "NoModify" 1
  WriteRegDWORD SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "NoRepair" 1
  
  ; Create uninstall registry key
  WriteRegStr SHCTX "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "QuietUninstallString" '"$INSTDIR\${UNINSTALL_EXECUTABLE_TARGET}" /S'
  
SectionEnd

Section "Desktop Shortcut" SecDesktop
  ; Create desktop shortcut
  CreateShortCut "$DESKTOP\${PRODUCT_NAME}.lnk" "$INSTDIR\${EXECUTABLE_TARGET}" "" "$INSTDIR\${EXECUTABLE_TARGET}" 0
SectionEnd

Section "Start Menu Shortcut" SecStartMenu
  ; Create start menu shortcut
  CreateDirectory "$SMPROGRAMS\$STARTMENU_FOLDER"
  CreateShortCut "$SMPROGRAMS\$STARTMENU_FOLDER\${PRODUCT_NAME}.lnk" "$INSTDIR\${EXECUTABLE_TARGET}" "" "$INSTDIR\${EXECUTABLE_TARGET}" 0
  CreateShortCut "$SMPROGRAMS\$STARTMENU_FOLDER\Uninstall ${PRODUCT_NAME}.lnk" "$INSTDIR\${UNINSTALL_EXECUTABLE_TARGET}" "" "$INSTDIR\${UNINSTALL_EXECUTABLE_TARGET}" 0
SectionEnd

Section "Uninstall" SecUninstall
  ; Remove files
  Delete "$INSTDIR\*.*"
  RMDir "$INSTDIR"
  
  ; Remove shortcuts
  Delete "$DESKTOP\${PRODUCT_NAME}.lnk"
  Delete "$SMPROGRAMS\$STARTMENU_FOLDER\${PRODUCT_NAME}.lnk"
  Delete "$SMPROGRAMS\$STARTMENU_FOLDER\Uninstall ${PRODUCT_NAME}.lnk"
  RMDir "$SMPROGRAMS\$STARTMENU_FOLDER"
  
  ; Remove registry entries
  DeleteRegKey SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"
  
  ; Remove uninstaller
  Delete "$INSTDIR\${UNINSTALL_EXECUTABLE_TARGET}"
SectionEnd

; ------------------------------
; Uninstaller
; ------------------------------
Section "Uninstall"
  Push $INSTDIR
  Call UnremoveFiles
  Pop $INSTDIR
  
  ; Remove uninstall registry key
  DeleteRegKey SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"
SectionEnd

Function .onInit
  ; Check if already installed
  ReadRegStr $0 HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "DisplayName"
  StrCmp $0 "${PRODUCT_NAME}" 0 +2
    Abort
FunctionEnd

Function unonInit
  ; Remove all files during uninstall
  ReadRegStr $INSTDIR HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "InstallLocation"
  IfEmpty +1
    RMDir /r $INSTDIR
FunctionEnd

Function .onInstStart
  ; Set installer properties
  SetShellVarContext all
FunctionEnd