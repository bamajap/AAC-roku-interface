@ECHO OFF
SET /P INPUT=Enter your Roku's IP address: 
IF "%INPUT%"=="" GOTO Error
ECHO The Roku IP address you entered was: %INPUT%.
ECHO If that is not correct, run this command file again and enter the correct IP address for your Roku.
setx ROKU_IP %INPUT% /M
GOTO End
:Error
ECHO You did not enter an IP address! Try again by running this command file again.
:End
pause