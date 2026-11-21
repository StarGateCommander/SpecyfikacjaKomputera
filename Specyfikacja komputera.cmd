@echo off
rem Dwuklik: zbiera parametry komputera do ogloszenia sprzedazy (schowek + plik na pulpicie).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Specyfikacja-komputera.ps1"
