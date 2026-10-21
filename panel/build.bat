@echo off
setlocal
cd /d "%~dp0"
set CSC=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe
set FW=C:\Windows\Microsoft.NET\Framework64\v4.0.30319
"%CSC%" /nologo /target:winexe /optimize+ /out:ChainedTeamsPanel.exe /r:System.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:"%FW%\System.Web.Extensions.dll" src\Panel.cs
if errorlevel 1 (echo Build failed. & exit /b 1)
echo Built ChainedTeamsPanel.exe
