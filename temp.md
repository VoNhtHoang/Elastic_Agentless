return [PSCustomObject]@{ "@timestamp" = $Event.TimeCreated.ToUniversalTime().ToString("o") host = @{ hostname = $env:COMPUTERNAME } event = @{ code = $Event.Id provider = $Event.ProviderName record_id = $Event.RecordId level = $Event.LevelDisplayName } user = @{ name = $EventData["TargetUserName"] } source = @{ ip = $EventData["IpAddress"] } process = @{ name = $EventData["ProcessName"] pid = $EventData["ProcessId"] } eventdata = $EventData message = $Event.FormatDescription() agent = @{ type = "powershell-agent" }


