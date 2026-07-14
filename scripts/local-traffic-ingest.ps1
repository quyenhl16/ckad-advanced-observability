$env:GO111MODULE = "on"
$env:GOTOOLCHAIN = "local"
$env:GOCACHE = "$PSScriptRoot\..\.cache\go-build"
$env:GOMODCACHE = "$PSScriptRoot\..\.cache\go-mod"
$env:ANALYTICS_URL = "http://localhost:8081"
$env:HTTP_ADDR = ":8080"
Set-Location "$PSScriptRoot\.."
go run ./cmd/traffic-ingest

