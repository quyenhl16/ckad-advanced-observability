$services = 8080, 8081, 8082, 8083
foreach ($port in $services) {
    Write-Host "Waiting for localhost:$port ..."
    do {
        Start-Sleep -Seconds 1
        $ready = Test-NetConnection -ComputerName localhost -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
    } until ($ready)
}
$clients = @(
    @{ device_type="router"; device_id="router-hcm-01"; cpu_usage_percent=72.5; memory_usage_percent=64.2; temperature_celsius=68.4; latency_ms=240; packet_loss_percent=2.1 },
    @{ device_type="switch"; device_id="switch-dn-01"; cpu_usage_percent=35.0; memory_usage_percent=42.8; temperature_celsius=51.2; latency_ms=48; packet_loss_percent=0.2 },
    @{ device_type="server"; device_id="server-api-01"; cpu_usage_percent=88.1; memory_usage_percent=79.4; temperature_celsius=74.0; latency_ms=165; packet_loss_percent=1.4 },
    @{ device_type="firewall"; device_id="firewall-edge-01"; cpu_usage_percent=61.3; memory_usage_percent=58.7; temperature_celsius=62.5; latency_ms=92; packet_loss_percent=0.7 },
    @{ device_type="access_point"; device_id="ap-floor-03"; cpu_usage_percent=45.6; memory_usage_percent=53.1; temperature_celsius=57.8; latency_ms=190; packet_loss_percent=3.5 }
)
foreach ($client in $clients) {
    $result = Invoke-RestMethod -Method Post -Uri "http://localhost:8080/api/v1/metrics" -ContentType "application/json" -Body ($client | ConvertTo-Json)
    Write-Host ("{0,-14} {1,-20} trace={2}" -f $client.device_type, $client.device_id, $result.trace_id) -ForegroundColor Green
}
Write-Host "Dashboard: http://localhost:8083" -ForegroundColor Cyan
