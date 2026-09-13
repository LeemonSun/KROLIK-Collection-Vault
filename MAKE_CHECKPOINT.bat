@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (
    py -3 tools\make_checkpoint.py --label manual --keep 20
) else (
    python tools\make_checkpoint.py --label manual --keep 20
)
if errorlevel 1 (
    echo.
    echo [KROLIK] Ошибка создания чекпоинта.
    pause
    exit /b 1
)
echo.
echo [KROLIK] Чекпоинт создан в соседней папке KROLIK_CHECKPOINTS.
pause
