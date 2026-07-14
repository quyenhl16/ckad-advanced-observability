$env:GO111MODULE = "on"
$env:GOTOOLCHAIN = "local"
$env:GOCACHE = "$PSScriptRoot\..\.cache\go-build"
$env:GOMODCACHE = "$PSScriptRoot\..\.cache\go-mod"
$env:ALERT_MANAGER_URL = "http://localhost:8082"
$env:ALERT_API_KEY = "local-secret"
$env:LATENCY_THRESHOLD_MS = "150"
$env:ANALYTICS_LOG_PATH = "$PSScriptRoot\..\data\analytics.jsonl"
$env:HTTP_ADDR = ":8081"
Set-Location "$PSScriptRoot\.."
go run ./cmd/analytics-engine

