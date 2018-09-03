@ECHO OFF
FOR /F "usebackq tokens=*" %%a IN (`wmic.exe COMPUTERSYSTEM GET DOMAIN /Value`) DO (
      @((ECHO %%a | findstr /i /c:"Domain=") && SET _str=%%a) > NUL 2>&1
)
FOR /F "tokens=2 delims=^=" %%a IN ("%_str%") do SET _COMPUTERDOMAIN=%%a

@ECHO ON
msiexec /q /i %LOGONSERVER%\ScriptLibrary\Install\Rapid7\Agent\files\agentInstaller-x86_64.msi TRANSFORMS=%LOGONSERVER%\ScriptLibrary\Install\Rapid7\Agent\files\agentInstaller-x86_64.mst CONFIGFILEPATH="%LOGONSERVER%\ScriptLibrary\Install\Rapid7\Agent\files" CUSTOMATTRIBUTES="%_COMPUTERDOMAIN%" /log "%LOGONSERVER%\ScriptLibrary\Install\Rapid7\Agent\logs\%COMPUTERNAME%_log.txt"
