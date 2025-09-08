@echo off
setlocal
cd /d %~dp0
docker build -t immgent-app1 .
start "" cmd /c "docker run --rm -p 3838:3838 -v "%cd%\data:/srv/shiny-server/data" immgent-app1"
start "" http://localhost:3838/app/
endlocal