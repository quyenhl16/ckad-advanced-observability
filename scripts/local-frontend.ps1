$env:GO111MODULE = "on"
$env:GOTOOLCHAIN = "local"
$env:GOCACHE = "$PSScriptRoot\..\.cache\go-build"
$env:GOMODCACHE = "$PSScriptRoot\..\.cache\go-mod"
$env:ANALYTICS_URL = "http://localhost:8081"
$env:ALERT_MANAGER_URL = "http://localhost:8082"
$env:HTTP_ADDR = ":8083"
Set-Location "$PSScriptRoot\.."
go run ./cmd/observability-frontend

