@echo off
rem Buduje SpecyfikacjaKomputera.exe z wbudowanym Specyfikacja-komputera.ps1.
rem Po kazdej zmianie skryptu .ps1 uruchom ponownie.
setlocal
set FW=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319
"%FW%\csc.exe" /nologo /target:winexe /optimize+ /platform:anycpu /codepage:65001 ^
  /out:"%~dp0SpecyfikacjaKomputera.exe" ^
  /resource:"%~dp0Specyfikacja-komputera.ps1",Specyfikacja-komputera.ps1 ^
  /r:System.Windows.Forms.dll "%~dp0Launcher.cs"
if errorlevel 1 (echo BLAD kompilacji & exit /b 1)
echo OK: %~dp0SpecyfikacjaKomputera.exe
