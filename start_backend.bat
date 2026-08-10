@echo off
REM hitran-viewer 后端一键启动脚本
REM 依赖：Anaconda（D:\anaconda），环境 hitran-viewer

set CONDA_ROOT=D:\anaconda
set ENV_NAME=hitran-viewer

call "%CONDA_ROOT%\Scripts\activate.bat" "%ENV_NAME%"
if errorlevel 1 (
    echo [错误] 无法激活 conda 环境 %ENV_NAME%
    echo 请先执行: conda env create -f environment.yml
    pause
    exit /b 1
)

REM 本地回环不走代理（MATLAB/浏览器访问后端用）
set NO_PROXY=127.0.0.1,localhost
set no_proxy=127.0.0.1,localhost

echo 启动 hitran-viewer 后端 ...
python "%~dp0backend\app.py"
pause
