@echo off

setlocal
set pwd="%cd%"

:: Setting the curl app's directory.
cd ..
set CURL_DIR="%cd%\curl-7.52.1"

cd %pwd%

for /f "usebackq tokens=*" %%i in (`type ..\ps\RokuIP.txt`) do (
    set "ROKU_IP=%%i"
)

"%CURL_DIR%\src\curl.exe" -d '' http://%ROKU_IP%:8060/%1

endlocal