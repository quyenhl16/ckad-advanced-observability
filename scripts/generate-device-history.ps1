param(
    [ValidateRange(2, 100)]
    [int]$Samples = 24,
    [string]$DeviceType = "server",
    [string]$DeviceID = "server-timeseries-01",
    [string]$TrafficURL = "http://localhost:8080/api/v1/metrics"
)

$allowedTypes = @("router", "switch", "server", "firewall", "access_point")
if ($DeviceType -notin $allowedTypes) {
    throw "DeviceType must be one of: $($allowedTypes -join ', ')"
}

$results = [System.Collections.Generic.List[object]]::new()
$startTime = (Get-Date).ToUniversalTime().AddMinutes(-($Samples - 1) * 5)

for ($index = 0; $index -lt $Samples; $index++) {
    $observedAt = $startTime.AddMinutes($index * 5)
    $wave = [math]::Sin($index / 3.0)
    $cpu = [math]::Round(52 + 30 * $wave, 1)
    $memory = [math]::Round(58 + ($index * 0.9) + 5 * [math]::Cos($index / 4.0), 1)
    $temperature = [math]::Round(48 + ($cpu * 0.32), 1)
    $latency = [math]::Round(70 + 75 * (1 + $wave), 0)
    $packetLoss = [math]::Round([math]::Max(0, ($latency - 100) / 45), 1)

    $metric = @{
        device_type = $DeviceType
        device_id = $DeviceID
        cpu_usage_percent = $cpu
        memory_usage_percent = [math]::Min($memory, 100)
        temperature_celsius = $temperature
        latency_ms = $latency
        packet_loss_percent = [math]::Min($packetLoss, 100)
        observed_at = $observedAt.ToString("o")
    }

    try {
        $response = Invoke-RestMethod -Method Post -Uri $TrafficURL -ContentType "application/json" -Body ($metric | ConvertTo-Json)
        $result = [pscustomobject]@{
            observed_at = $observedAt.ToString("o")
            device_type = $DeviceType
            device_id = $DeviceID
            cpu_usage_percent = $cpu
            memory_usage_percent = $metric.memory_usage_percent
            temperature_celsius = $temperature
            latency_ms = $latency
            packet_loss_percent = $metric.packet_loss_percent
            trace_id = $response.trace_id
        }
        $results.Add($result)
        Write-Host ("[{0,2}/{1}] {2} CPU={3,5}% RAM={4,5}% temp={5,5}C latency={6,3}ms trace={7}" -f ($index + 1), $Samples, $observedAt.ToString("HH:mm"), $cpu, $metric.memory_usage_percent, $temperature, $latency, $response.trace_id)
    }
    catch {
        Write-Error "Failed to send sample $($index + 1): $($_.Exception.Message)"
        exit 1
    }
}

$outputDirectory = Join-Path $PSScriptRoot "..\data"
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$outputPath = Join-Path $outputDirectory "device-history.csv"
$results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
$filterURL = "http://localhost:8083/?device_type=$DeviceType&device_id=$DeviceID"

Write-Host "`nGenerated $($results.Count) time-series samples for $DeviceID." -ForegroundColor Green
Write-Host "History data: $outputPath" -ForegroundColor Cyan
Write-Host "Device history: $filterURL" -ForegroundColor Cyan
