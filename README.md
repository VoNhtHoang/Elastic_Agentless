# Elastic Agentless



# Command and Run / Fix / Change Content
(Set-ExecutionPolicy RemoteSigned -Scope LocalMachine) ; powershell -File "C:\Users\WinIoTAgentless\Documents\Agentless\agent.ps1"

auditpol /set /subcategory:"File System" /success:enable /failure:enable
auditpol /get /category:* | findstr /i "Success Failure"
