@echo off
REM build-offline.cmd - compile the bundled minecraft-numen with NO network.
REM Sets its own GRADLE_USER_HOME / JAVA_HOME and runs Gradle in --offline mode.
setlocal
set "ROOT=%~dp0"
set "GRADLE_USER_HOME=%ROOT%gradle-home"
set "JAVA_HOME=%ROOT%jdk\jdk-21.0.11+10"
set "PATH=%JAVA_HOME%\bin;%PATH%"
set "GRADLE_OPTS="

REM Point any stray HTTP at a dead port so failures are fast and explicit
REM (never a silent hang).  Offline cache hits are used before any network.
set "DEADPROXY=-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=1 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=1"

cd /d "%ROOT%src"
echo [build-offline] GRADLE_USER_HOME=%GRADLE_USER_HOME%
echo [build-offline] JAVA_HOME=%JAVA_HOME%
echo [build-offline] gradle --offline %*
call "%ROOT%gradle-9.2.0\bin\gradle.bat" --offline --no-daemon --no-build-cache %DEADPROXY% %*
set "RC=%ERRORLEVEL%"
echo [build-offline] exit=%RC%
exit /b %RC%
