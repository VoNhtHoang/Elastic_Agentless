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

$global:lastRecordId = [long](Get-Content $stateRecordFile)
$global:eventQueue =
    [System.Collections.ArrayList]::Synchronized(
        (New-Object System.Collections.ArrayList)
    )

$global:lastFlush = Get-Date


Write-Host "[+] Script Agent Started" -ForegroundColor Cyan
Write-Host "[+] Last RecordId: $($global:lastRecordId)" -ForegroundColor Cyan
Write-Host "[i] Checking log from $logName per $intervalTime seconds " -ForegroundColor Cyan

# ----------------- FUNCTION --------------------
function eventConverter { 
    param( 
        $eventLog 
    ) 

    if ($null -eq $eventLog) {
        return $null 
    }

    # ------------------------- # Timestamp # ------------------------- 
    $timestamp = (Get-Date).ToString("o") 
    
    try { 
        if ($eventLog.TimeCreated) { 
            $timestamp = $eventLog.TimeCreated.ToString("o") 
        } 
    } 
    catch {

    } 

    # ------------------------- # Message # ------------------------- 
    $message = "" 
    try { 
        $message = $eventLog.FormatDescription() 
        if ($null -eq $message) { 
            $message = "" 
        } 
    } 
    catch {
        "[ERR] Message: $_" | Out-File C:\ProgramData\ElasticAgentlessScript\err.txt -Append
    } 

    # ------------------------- # EventData # ------------------------- 
    $eventData = @{}

    try {

        $xmlData = [xml]$eventLog.ToXml()

        if ($xmlData.Event.EventData) {

            $nodes = $xmlData.Event.EventData.Data

            if ($nodes) {

                foreach ($node in @($nodes)) {

                    if (
                        $null -ne $node -and
                        $null -ne $node.Name -and
                        ![string]::IsNullOrWhiteSpace($node.Name)
                    ) {
                        $eventData[$node.Name] = $node.'#text'
                    }
                }
            }
        }
    }
    catch {
        "[ERR] XML Parse: $($_.Exception.Message)" |
            Out-File C:\ProgramData\ElasticAgentlessScript\err.txt -Append
    }
    
    # ------------------------- # Safe fields # ------------------------- 
    $eventId = $null 
    $provider = "" 
    $level = "" 
    $recordId = 0 
    $task = "" 
    
    try { $eventId = $eventLog.Id } catch {} 
    try { $provider = $eventLog.ProviderName } catch {} 
    try { $level = $eventLog.LevelDisplayName } catch {} 
    try { $recordId = $eventLog.RecordId } catch {} 
    try { $task = $eventLog.TaskDisplayName } catch {} 

    # ------------------------- # Return object # ------------------------- 
    $customRes = $null
    try{ 
        $customRes = [PSCustomObject]@{ 
            "@timestamp" = $timestamp 
            host = @{ 
                hostname = $env:COMPUTERNAME 
            } 
            event = @{ 
                code = $eventId 
                provider = $provider 
                level = $level 
                record_id = $recordId 
                task = $task 
            } 
            winlog = @{ channel = $LogName } 
            agent = @{ type = "Powershell-Agentless" } 
            user = @{ name = $eventData["TargetUserName"] } 
            source = @{ ip = $eventData["IpAddress"] } 
            process = @{ name = $eventData["ProcessName"] 
            pid = $eventData["ProcessId"] } 
            logon = @{ type = $eventData["LogonType"] } 
            eventdata = $eventData 
            message = $message 
        } 
    }
    catch{
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
    return $customRes
}

# --------------- On Startup --------------
# Write-Host "[i] Replaying missed events..."

# $recoveryQuery = @"
# <QueryList>
#     <Query Id="0" Path="$LogName"> 
#         <Select Path="$LogName"> 
#             *[System[(EventRecordID > $($global:lastRecordId))]] 
#         </Select> 
#     </Query> 
# </QueryList>
# "@
        
# try { 
#     $missedEvents = Get-WinEvent -FilterXml $recoveryQuery
    
#     foreach ($eventLog in $missedEvents) { 
#         [void]$global:eventQueue.Add( (eventConverter $eventLog) )     
#         $global:lastRecordId = $eventLog.RecordId 
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


Register-ObjectEvent `
    -InputObject $watcher `
    -EventName EventRecordWritten `
    -Action {
        try{
            $record = $Event.SourceEventArgs.EventRecord

            if ($null -eq $record){
                return
            }

            if ($record.RecordId -le $global:lastRecordId) { 
                return
            }

            $objEvent = eventConverter $record
            if ($objEvent -eq $null){
                "[ERR] objNull: $_" | Out-File C:\ProgramData\ElasticAgentlessScript\err.txt -Append
            }
            
            [void] $global:eventQueue.Add($objEvent)
            
            $global:lastRecordId = $record.RecordId
            
        }
        catch{            
            "[ERR] ObjectEvent: $($_.Exception.Message) | $($_.InvocationInfo.PositionMessage)
 | $($_.ScriptStackTrace) | $($_.Exception.GetType().FullName)" | Out-File C:\ProgramData\ElasticAgentlessScript\err.txt -Append
        }
    }

# -------------------- Powershell >5.1 ----------------------
# $watcher.add_EventRecordWritten({
#     param($sender,$e)

#     $record = $e.EventRecord

#     $obj = eventConverter $record

#     [void]$global:eventQueue.Add($obj)
# })

# $watcher.add_EventRecordWritten({

#     param($sender,$e)

#     try {

#         Write-Host "NEW EVENT"

#         $record = $e.EventRecord

#         Write-Host $record.Id

#     }
#     catch {
#         $_ | Out-File C:\temp\err.txt -Append
#     }
# })

$watcher.Enabled = $true


# -------------- FLUSH LOOP ----------------------
Write-Host "[i] Realtime watcher started."
while ($true)
{
    try
    {
        $needFlush = $false

        if ($global:eventQueue.Count -ge $batchSize){
            $needFlush = $true
        }

        if (
            ((Get-Date) - $global:lastFlush).TotalSeconds -ge $intervalTime -and `
            $global:eventQueue.Count -gt 0
        ){
            $needFlush = $true
        }

        if ($needFlush) { 
            $payLoad = $global:eventQueue.ToArray() 
            $jsonBody = $payLoad | ConvertTo-Json -Depth 20 -Compress 

            $jsonBody | Out-File $jsonLogFile -Encoding utf8 -Append
            # Invoke-RestMethod `
            #     -Uri $LogstashUrl `
            #     -Method POST `
            #     -Body $jsonBody `
            #     -ContentType "application/json" `
            #     -TimeoutSec 30 
        
            $global:lastRecordId | Out-File $stateRecordFile -Force
            $global:eventQueue.Clear()
            $global:lastFlush = Get-Date
            
            Write-Host "[i] $(Get-Date -Format HH:mm:ss) - Sent batch. Last Record ID: $global:lastRecordId" 

            $needFlush = $false
        }

    } 
    catch { 
        Write-Host "[ERR] Error Occurred: $_" 
    }

    # Start-Sleep -Seconds 1
     Wait-Event -Timeout 1
}

