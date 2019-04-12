@ECHO OFF
echo Setting the curl app's directory.
cd ..
set fullCurlDir="%cd%\curl-7.52.1"
setx CURL_DIR "%fullCurlDir%" /M
echo CURL_DIR = %fullCurlDir%
echo[
