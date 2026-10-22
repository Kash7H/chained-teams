@echo off
set FW=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319
%FW%\csc.exe /nologo /optimize+ /platform:x64 /target:exe /out:"%~dp0ChainedTeams.exe" /r:%FW%\System.Web.Extensions.dll /r:%FW%\System.IO.Compression.dll /r:%FW%\System.IO.Compression.FileSystem.dll "%~dp0src\ChainedTeams.cs" "%~dp0src\Updater.cs"
