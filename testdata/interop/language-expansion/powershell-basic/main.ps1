function Invoke-Users {
    Get-Users
}

class Worker {
    [void] Run() {
        Write-Host "ok"
    }
}
