return [PSCustomObject]@{ "@timestamp" = $Event.TimeCreated.ToUniversalTime().ToString("o") host = @{ hostname = $env:COMPUTERNAME } event = @{ code = $Event.Id provider = $Event.ProviderName record_id = $Event.RecordId level = $Event.LevelDisplayName } user = @{ name = $EventData["TargetUserName"] } source = @{ ip = $EventData["IpAddress"] } process = @{ name = $EventData["ProcessName"] pid = $EventData["ProcessId"] } eventdata = $EventData message = $Event.FormatDescription() agent = @{ type = "powershell-agent" }



function eventConverter {
    param (
        $eventLog
    )
    
    # $eventData = @{}
    
      $logContent = "`
    eventLog null: $($null -eq $eventLog)`
    Fullname: $($eventLog.GetType().FullName)
    ID: $($eventLog.RecordId)`
    EventId:$($eventLog.Id)
    Time: $($eventLog.TimeCreated.ToUniversalTime())`
    Task: $task`
    Level: $level`
    =============================================================="

    $logContent | Out-File "C:\ProgramData\ElasticAgentlessScript\test_event.txt" -Append
    try{

        $xmlData = [xml]$eventLog.ToXml()

        $eventData = @{}

        if ($xmlData.Event.EventData){  
            foreach ($node in $xmlData.Event.EventData.Data) {

                if (![string]::IsNullOrWhiteSpace($node.Name)) {

                    $eventData[$node.Name] = $node.'#text'
                }
            }
        }
    }
    catch {
        return [PSCustomObject]@{ 
                    "@timestamp" = if ($eventLog.TimeCreated) {
                        $eventLog.TimeCreated.ToString("o")
                    }
                    else {
                        (Get-Date).ToString("o")
                    }
                    
                    host = @{ 
                        hostname = $env:COMPUTERNAME
                    } 
                    
                    event = @{ 
                        code = $eventLog.Id 
                        provider = $eventLog.ProviderName 
                        record_id = $eventLog.RecordId 
                    } 
                    
                    message = $eventLog.FormatDescription() # $eventLog.FormatDescription()
                    
                    parse_error = $true }
    }

    return [PSCustomObject]@{ 
                    "@timestamp" = if ($eventLog.TimeCreated) {
                        $eventLog.TimeCreated.ToString("o")
                    }
                    else {
                        (Get-Date).ToString("o")
                    }
                    
                    host = @{ 
                        hostname = $env:COMPUTERNAME
                    } 
                    event = @{ 
                        code = $eventLog.Id 
                        provider = $eventLog.ProviderName 
                        level = $eventLog.LevelDisplayName 
                        record_id = $eventLog.RecordId 
                        task = $eventLog.TaskDisplayName 
                    } 
                        
                    winlog = @{ channel = $LogName } 
                        
                    agent = @{ type = "Powershell-Agentless" } 

                    user = @{ name = $eventData["TargetUserName"] } 
                    source = @{ ip = $eventData["IpAddress"] } 
                    
                    process = @{ name = $eventData["ProcessName"] 
                    pid = $eventData["ProcessId"] } 
                    logon = @{ type = $eventData["LogonType"] } 
                    eventdata = $eventData 
                    message = $eventLog.FormatDescription()
                }
}