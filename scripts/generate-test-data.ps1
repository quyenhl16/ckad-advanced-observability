param(
    [ValidateRange(1, 500)]
    [int]$Count = 50,
    [string]$TrafficURL = "http://localhost:8080/api/v1/metrics"
)

$deviceTypes = @("router", "switch", "server", "firewall", "access_point")
$random = [System.Random]::new(20260713)
$results = [System.Collections.Generic.List[object]]::new()

for ($index = 1; $index -le $Count; $index++) {
    $deviceType = $deviceTypes[($index - 1) % $deviceTypes.Count]
    $sequence = [int][math]::Ceiling($index / $deviceTypes.Count)
    $deviceID = "{0}-test-{1}" -f $deviceType, $sequence.ToString("D3")

    # Every third sample exceeds the configured 150 ms latency threshold.
    $latency = if ($index % 3 -eq 0) { $random.Next(160, 350) } else { $random.Next(10, 145) }
    $metric = @{
        device_type = $deviceType
        device_id = $deviceID
        cpu_usage_percent = [math]::Round($random.NextDouble() * 85 + 5, 1)
        memory_usage_percent = [math]::Round($random.NextDouble() * 80 + 10, 1)
        temperature_celsius = [math]::Round($random.NextDouble() * 45 + 35, 1)
        latency_ms = $latency
        packet_loss_percent = [math]::Round($random.NextDouble() * 5, 1)
    }

    try {
        $response = Invoke-RestMethod -Method Post -Uri $TrafficURL -ContentType "application/json" -Body ($metric | ConvertTo-Json)
        $status = if ($latency -gt 150) { "THRESHOLD_EXCEEDED" } else { "NORMAL" }
        $result = [pscustomobject]@{
            device_type = $deviceType
            device_id = $deviceID
            trace_id = $response.trace_id
            latency_ms = $latency
            expected_status = $status
        }
        $results.Add($result)
        Write-Host ("[{0,2}/{1}] {2,-14} {3,-24} latency={4,3} trace={5}" -f $index, $Count, $deviceType, $deviceID, $latency, $response.trace_id)
    }
    catch {
        Write-Error "Failed to send metric for ${deviceID}: $($_.Exception.Message)"
        exit 1
    }
}

$outputDirectory = Join-Path $PSScriptRoot "..\data"
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$outputPath = Join-Path $outputDirectory "test-traces.csv"
$results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8

Write-Host "`nGenerated $($results.Count) client metrics." -ForegroundColor Green
Write-Host "Trace mapping: $outputPath" -ForegroundColor Cyan
Write-Host "Dashboard: http://localhost:8083" -ForegroundColor Cyan
