@echo off
:: Fix script: restores official Roblox access by cleaning any hijacked entries
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

set HOSTS=%WINDIR%\System32\drivers\etc\hosts
set TEMP_HOSTS=%TEMP%\hosts_clean_%RANDOM%.txt

echo [*] Restoring %HOSTS% ...
findstr /V /I "roblox.com rbxcdn.com pekora.rip oldrrt.xyz 74.248.20.23" "%HOSTS%" > "%TEMP_HOSTS%"
copy /Y "%TEMP_HOSTS%" "%HOSTS%" >nul
del /F /Q "%TEMP_HOSTS%" >nul

echo [*] Flushing DNS cache...
ipconfig /flushdns >nul

echo [+] SUCCESS: Windows hosts file has been cleaned.
echo [+] Official Roblox is restored.
echo.
pause
