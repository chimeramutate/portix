; Portix Windows installer (NSIS, Modern UI 2).
;
; Build (from any folder; paths below are relative to this script):
;   makensis /DAPP_VERSION=1.2.3 /DSOURCE_DIR=C:\path\to\Release ^
;            /DOUT_FILE=C:\path\to\portix-windows-1.2.3.exe portix.nsi
;
; SOURCE_DIR is the Flutter release folder (portix.exe, *.dll, data\) with
; portix_serv.dll, portix_rdp.dll and the VC++ runtime already copied in;
; build-installer.ps1 does that and then runs this script.
;
; Optional branding, used when present in resources\installer-icons\
; (24-bit BMP; 32-bit/alpha BMPs are rejected by NSIS):
;   welcome.bmp  164x314, left side of the welcome/finish pages
;   header.bmp   150x57,  top right of the other pages

Unicode true
ManifestDPIAware true
SetCompressor /SOLID lzma

!ifndef APP_VERSION
  !define APP_VERSION "0.0.0"
!endif
!ifndef SOURCE_DIR
  !error "Pass /DSOURCE_DIR=<Flutter Release folder>"
!endif
!ifndef PRODUCT_VERSION
  ; Four numbers, as Windows file versions are.
  !define PRODUCT_VERSION "${APP_VERSION}.0"
!endif
!ifndef OUT_FILE
  !define OUT_FILE "portix-windows-${APP_VERSION}.exe"
!endif

!define APP_NAME      "Portix"
!define APP_EXE       "portix.exe"
!define PUBLISHER     "Portix"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Portix"
!define ICON          "..\..\portix_app\windows\runner\resources\app_icon.ico"
!define BRANDING      "resources\installer-icons"

Name "${APP_NAME} ${APP_VERSION}"
OutFile "${OUT_FILE}"
InstallDir "$PROGRAMFILES64\${APP_NAME}"
; An upgrade installs over the previous location.
InstallDirRegKey HKLM "${UNINSTALL_KEY}" "InstallLocation"
RequestExecutionLevel admin
BrandingText "${APP_NAME} ${APP_VERSION}"

VIProductVersion "${PRODUCT_VERSION}"
VIAddVersionKey /LANG=0 "ProductName" "${APP_NAME}"
VIAddVersionKey /LANG=0 "FileDescription" "${APP_NAME} Setup"
VIAddVersionKey /LANG=0 "FileVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=0 "ProductVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=0 "CompanyName" "${PUBLISHER}"
VIAddVersionKey /LANG=0 "LegalCopyright" "${PUBLISHER}"

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "x64.nsh"

; ── Look ────────────────────────────────────────────────────────────────
!define MUI_ICON   "${ICON}"
!define MUI_UNICON "${ICON}"
!define MUI_ABORTWARNING
!define MUI_UNABORTWARNING
!define MUI_COMPONENTSPAGE_SMALLDESC
!if /FileExists "${BRANDING}\welcome.bmp"
  !define MUI_WELCOMEFINISHPAGE_BITMAP   "${BRANDING}\welcome.bmp"
  !define MUI_UNWELCOMEFINISHPAGE_BITMAP "${BRANDING}\welcome.bmp"
!endif
!if /FileExists "${BRANDING}\header.bmp"
  !define MUI_HEADERIMAGE
  !define MUI_HEADERIMAGE_RIGHT
  !define MUI_HEADERIMAGE_BITMAP "${BRANDING}\header.bmp"
!endif

; Remember the language picked at the first install.
!define MUI_LANGDLL_REGISTRY_ROOT      HKLM
!define MUI_LANGDLL_REGISTRY_KEY       "${UNINSTALL_KEY}"
!define MUI_LANGDLL_REGISTRY_VALUENAME "InstallerLanguage"
!define MUI_LANGDLL_ALLLANGUAGES

; ── Install steps ───────────────────────────────────────────────────────
!define MUI_WELCOMEPAGE_TITLE "$(WelcomeTitle)"
!define MUI_WELCOMEPAGE_TEXT  "$(WelcomeText)"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN      "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "$(LaunchApp)"
!insertmacro MUI_PAGE_FINISH

; ── Uninstall steps ─────────────────────────────────────────────────────
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_COMPONENTS
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Indonesian"
!insertmacro MUI_RESERVEFILE_LANGDLL

; ── Texts ───────────────────────────────────────────────────────────────
LangString WelcomeTitle ${LANG_ENGLISH} "Welcome to ${APP_NAME} ${APP_VERSION} Setup"
LangString WelcomeTitle ${LANG_INDONESIAN} "Selamat datang di instalasi ${APP_NAME} ${APP_VERSION}"
LangString WelcomeText ${LANG_ENGLISH} "${APP_NAME} is an SSH, SFTP and RDP workspace.$\r$\n$\r$\nSetup will install it on this computer. Your profiles and settings from an earlier version are kept.$\r$\n$\r$\nClick Next to continue."
LangString WelcomeText ${LANG_INDONESIAN} "${APP_NAME} adalah workspace SSH, SFTP dan RDP.$\r$\n$\r$\nInstaller akan memasangnya di komputer ini. Profil dan pengaturan dari versi sebelumnya tetap disimpan.$\r$\n$\r$\nKlik Next untuk melanjutkan."
LangString LaunchApp ${LANG_ENGLISH} "Launch ${APP_NAME}"
LangString LaunchApp ${LANG_INDONESIAN} "Jalankan ${APP_NAME}"
LangString AppRunning ${LANG_ENGLISH} "${APP_NAME} is running. Close it, then click Retry."
LangString AppRunning ${LANG_INDONESIAN} "${APP_NAME} sedang berjalan. Tutup aplikasinya, lalu klik Retry."
LangString Needs64Bit ${LANG_ENGLISH} "${APP_NAME} needs 64-bit Windows."
LangString Needs64Bit ${LANG_INDONESIAN} "${APP_NAME} membutuhkan Windows 64-bit."

LangString SecAppName ${LANG_ENGLISH} "${APP_NAME} (required)"
LangString SecAppName ${LANG_INDONESIAN} "${APP_NAME} (wajib)"
LangString SecAppDesc ${LANG_ENGLISH} "The application and its libraries."
LangString SecAppDesc ${LANG_INDONESIAN} "Aplikasi beserta library-nya."
LangString SecStartName ${LANG_ENGLISH} "Start Menu shortcut"
LangString SecStartName ${LANG_INDONESIAN} "Shortcut Start Menu"
LangString SecStartDesc ${LANG_ENGLISH} "Adds ${APP_NAME} to the Start Menu."
LangString SecStartDesc ${LANG_INDONESIAN} "Menambahkan ${APP_NAME} ke Start Menu."
LangString SecDesktopName ${LANG_ENGLISH} "Desktop shortcut"
LangString SecDesktopName ${LANG_INDONESIAN} "Shortcut Desktop"
LangString SecDesktopDesc ${LANG_ENGLISH} "Puts a ${APP_NAME} icon on the desktop."
LangString SecDesktopDesc ${LANG_INDONESIAN} "Menaruh ikon ${APP_NAME} di desktop."

LangString UnSecAppName ${LANG_ENGLISH} "${APP_NAME}"
LangString UnSecAppName ${LANG_INDONESIAN} "${APP_NAME}"
LangString UnSecAppDesc ${LANG_ENGLISH} "Removes the application and its shortcuts."
LangString UnSecAppDesc ${LANG_INDONESIAN} "Menghapus aplikasi dan shortcut-nya."
LangString UnSecDataName ${LANG_ENGLISH} "Remove my data"
LangString UnSecDataName ${LANG_INDONESIAN} "Hapus data saya"
LangString UnSecDataDesc ${LANG_ENGLISH} "Also deletes your profiles, settings, saved sessions and session logs. Leave unchecked to keep them for a later install."
LangString UnSecDataDesc ${LANG_INDONESIAN} "Ikut menghapus profil, pengaturan, sesi tersimpan dan log sesi. Biarkan tidak dicentang untuk menyimpannya bagi instalasi berikutnya."

; ── Helpers ─────────────────────────────────────────────────────────────
; A running portix.exe is locked for writing; ask until it is closed.
!macro EnsureNotRunning UN
  Function ${UN}EnsureNotRunning
    retry:
      IfFileExists "$INSTDIR\${APP_EXE}" 0 done
      ClearErrors
      FileOpen $0 "$INSTDIR\${APP_EXE}" a
      IfErrors 0 closed
      MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "$(AppRunning)" /SD IDCANCEL IDRETRY retry
      Abort
    closed:
      FileClose $0
    done:
  FunctionEnd
!macroend
!insertmacro EnsureNotRunning ""
!insertmacro EnsureNotRunning "un."

; ── Install ─────────────────────────────────────────────────────────────
Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "$(Needs64Bit)" /SD IDOK
    Abort
  ${EndIf}
  SetRegView 64
  SetShellVarContext all
  !insertmacro MUI_LANGDLL_DISPLAY
FunctionEnd

Section "$(SecAppName)" SecApp
  SectionIn RO
  Call EnsureNotRunning
  SetOutPath "$INSTDIR"
  ; Assets of the previous version must not linger next to the new ones.
  RMDir /r "$INSTDIR\data"
  File /r "${SOURCE_DIR}\*.*"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "Publisher" "${PUBLISHER}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "${UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKLM "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTALL_KEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  WriteRegDWORD HKLM "${UNINSTALL_KEY}" "EstimatedSize" $0
SectionEnd

Section "$(SecStartName)" SecStart
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\Uninstall ${APP_NAME}.lnk" "$INSTDIR\Uninstall.exe"
SectionEnd

Section "$(SecDesktopName)" SecDesktop
  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecApp} "$(SecAppDesc)"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecStart} "$(SecStartDesc)"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop} "$(SecDesktopDesc)"
!insertmacro MUI_FUNCTION_DESCRIPTION_END

; ── Uninstall ───────────────────────────────────────────────────────────
Function un.onInit
  SetRegView 64
  SetShellVarContext all
  !insertmacro MUI_UNGETLANGUAGE
FunctionEnd

Section "un.$(UnSecAppName)" UnSecApp
  SectionIn RO
  Call un.EnsureNotRunning
  ; Only what the installer put there: the folder may hold other files if
  ; it was not a dedicated one, so it is never deleted recursively.
  Delete "$INSTDIR\${APP_EXE}"
  Delete "$INSTDIR\*.dll"
  RMDir /r "$INSTDIR\data"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"

  Delete "$DESKTOP\${APP_NAME}.lnk"
  RMDir /r "$SMPROGRAMS\${APP_NAME}"
  DeleteRegKey HKLM "${UNINSTALL_KEY}"
SectionEnd

; Unchecked by default (/o): data survives unless the user asks.
Section /o "un.$(UnSecDataName)" UnSecData
  SetShellVarContext current
  ; Profiles and session logs. Saved passwords stay in Windows Credential
  ; Manager.
  RMDir /r "$PROFILE\.portix"
  ; Settings and saved sessions (Flutter's application support folder,
  ; named after CompanyName\ProductName in windows\runner\Runner.rc).
  RMDir /r "$APPDATA\com.example\Portix"
  RMDir "$APPDATA\com.example"
  SetShellVarContext all
SectionEnd

!insertmacro MUI_UNFUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${UnSecApp} "$(UnSecAppDesc)"
  !insertmacro MUI_DESCRIPTION_TEXT ${UnSecData} "$(UnSecDataDesc)"
!insertmacro MUI_UNFUNCTION_DESCRIPTION_END
