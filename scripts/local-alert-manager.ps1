$env:GO111MODULE = "on"
$env:GOTOOLCHAIN = "local"
$env:GOCACHE = "$PSScriptRoot\..\.cache\go-build"
$env:GOMODCACHE = "$PSScriptRoot\..\.cache\go-mod"
$env:ALERT_REPOSITORY = "memory"
if ([string]::IsNullOrWhiteSpace($env:ALERT_API_KEY)) {
    throw "Set ALERT_API_KEY before starting local services"
}
$env:HTTP_ADDR = ":8082"
Set-Location "$PSScriptRoot\.."
go run ./cmd/alert-manager
