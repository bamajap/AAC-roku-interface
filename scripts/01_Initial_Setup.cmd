@ECHO OFF
set pwd="%cd%"

::Initialize the curl app directory variable.
call Set_curl_dir.cmd

cd %pwd%

::Initialize the Roku's IP address variable.
call Set_Roku_IP.cmd
