# --------------------------------
# Agentless Powershell Agent :))
# --------------------------------

# -------------- CONFIG -----------
$logStashUrl = ""

$stateRecordFile = "C:\ProgramData\ElasticAgentlessScript\state_record.txt"
$jsonLogFile = "C:\ProgramData\ElasticAgentlessScript\log.json"
$logName = "Security"


$intervalTime = 20 # second
$batchSize = 100

# -------------- INIT -------------
# taoj thư mục lưu nếu chưa exists
$stateRecordDir = Split-Path $stateRecordFile

if (!(Test-Path $stateRecordDir)){
    New-Item -ItemType Directory -Path $stateRecordDir -Force | Out-Null

}

if (!(Test-Path $stateRecordFile)){
    "0" | Out-File $stateRecordFile -Force

}

$script:lastRecordId = [long](Get-Content $stateRecordFile)
$script:eventQueue = New-Object System.Collections.ArrayList

$script:lastFlush = Get-Date


Write-Host "[+] Script Agent Started" -ForegroundColor Cyan
Write-Host "[+] Last RecordId: $($script:lastRecordId)" -ForegroundColor Cyan
Write-Host "[i] Checking log from $logName per $intervalTime seconds " -ForegroundColor Cyan

# ----------------- FUNCTION --------------------
function eventConverter {
    param (
        $eventLog
    )
    
    $eventData = @{}
    
    try{

        $xmlData = [xml]$eventLog.ToXml()

        $eventData = @{}

        if ($xmlData.Event.EventData){  
            foreach ( $node in $xmlData.Event.EventData.Data){
                $name = $node.Name

                if (![string]::IsNullOrWhiteSpace($Name)) {
                    $eventData[$name] = $node.'#text'
                }
            }
        }
    }
    catch {
        return [PSCustomObject]@{ 
                    "@timestamp" = $eventLog.TimeCreated.ToUniversalTime().ToString("o") 
                    
                    host = @{ 
                        hostname = $eventLog.MachineName 
                    } 
                    
                    event = @{ 
                        code = $eventLog.Id 
                        provider = $eventLog.ProviderName 
                        record_id = $eventLog.RecordId 
                    } 
                    
                    message = $eventLog.Message 
                    
                    parse_error = $true }
    }

    return [PSCustomObject]@{ 
                    "@timestamp" = $eventLog.TimeCreated.ToUniversalTime().ToString("o") 
                    
                    host = @{ 
                        hostname = $eventLog.MachineName
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
                    message = $eventLog.Message 
                }

    
}

# --------------- On Startup --------------
# Write-Host "[i] Replaying missed events..."

# $recoveryQuery = @"
# <QueryList>
#     <Query Id="0" Path="$LogName"> 
#         <Select Path="$LogName"> 
#             *[System[(EventRecordID > $($script:lastRecordId))]] 
#         </Select> 
#     </Query> 
# </QueryList>
# "@
        
# try { 
#     $missedEvents = Get-WinEvent -FilterXml $recoveryQuery
    
#     foreach ($eventLog in $missedEvents) { 
#         [void]$script:eventQueue.Add( (eventConverter $eventLog) )     
#         $script:lastRecordId = $eventLog.RecordId 
#     } 
    
#     Write-Host "[i] Recovery events: $($missedEvents.Count)" -ForegroundColor Green
    
# } 
# catch { 
#     Write-Host "[ERR] Error occurred: $_"
# }


# ---------------- Realtime Callback ------------
$query = New-Object System.Diagnostics.Eventing.Reader.EventLogQuery( 
        $logName, 
        [System.Diagnostics.Eventing.Reader.PathType]::LogName 
    )

$watcher = New-Object System.Diagnostics.Eventing.Reader.EventLogWatcher($query)
$watcher.Enabled = $true

Register-ObjectEvent `
    -InputObject $watcher `
    -EventName EventRecordWritten `
    -Action {
        # $record = $eventLog.SourceEventArgs.EventRecord

        # if ($null -eq $record){
        #     return
        # }

        # if ($record.RecordId -le $script:lastRecordId) { 
        #     return 
        # }

        # [void] $script:eventQueue.Add(
        #     (eventConverter $record)
        # )

        # $script:lastRecordId = $record.RecordId
        $record = $Event.SourceEventArgs.EventRecord

        if ($null -eq $record) {
            Write-Host "NULL"
        }
        else {
            Write-Host $record.Id
        }
    }

Write-Host "[i] Realtime watcher started."

# -------------- FLUSH LOOP ----------------------
while ($true)
{
    try
    {
        $needFlush = $false

        if ($script:eventQueue.Count -ge $batchSize){
            $needFlush = $true

        }

        if (
            ((Get-Date) - $script:lastFlush).TotalSeconds -ge $intervalTime -and `
            $script:eventQueue.Count -gt 0
        ){
            $needFlush = $true
        }

        if ($needFlush) { 
            $payLoad = $script:eventQueue.ToArray() 
            $jsonBody = $payLoad | ConvertTo-Json -Depth 20 -Compress 

            $jsonBody | Out-File $jsonLogFile -Encoding utf8 -Force
            # Invoke-RestMethod `
            #     -Uri $LogstashUrl `
            #     -Method POST `
            #     -Body $jsonBody `
            #     -ContentType "application/json" `
            #     -TimeoutSec 30 
        
            $script:lastRecordId | Out-File $stateRecordFile -Force 
            $script:eventQueue.Clear()
            $script:lastFlush = Get-Date
            
            Write-Host "[i] $(Get-Date -Format HH:mm:ss) - Sent batch. Last Record ID: $script:lastRecordId" } 
    } 
    catch { 
        Write-Host "[ERR] Error Occurred: $_" 
    }

    Start-Sleep -Seconds 1
}

