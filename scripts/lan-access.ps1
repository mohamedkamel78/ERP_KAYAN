#requires -version 5.0
<#
    KAYAN ERP - who can reach this machine, and from which address.

    A server installation is meant to be opened from the phones and desks on
    the same network, and (later) from outside the building through an HTTPS
    proxy. Both go wrong in the same way: somebody guesses an address. This
    script prints the addresses that actually work on this machine, says
    whether the firewall lets the port through, and - only when it is asked
    with -OpenFirewall and is running elevated - opens it.

    It changes nothing else. No port is closed, no rule is deleted, no service
    is restarted, and no password is read or written. Removing a firewall rule
    is a thing a person does on purpose with the command this script prints.

    .EXAMPLE
      scripts\lan-access.ps1
      scripts\lan-access.ps1 -OpenFirewall
      scripts\lan-access.ps1 -Port 3000 -CheckHttps
#>

[CmdletBinding()]
param(
    [int]$Port = 3000,
    [switch]$OpenFirewall,
    [switch]$CheckHttps
)

$ErrorActionPreference = 'SilentlyContinue'

function Write-Line($Text, $Color) {
    if ($Color) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
}

$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Line ''
Write-Line "  KAYAN ERP - reaching port $Port from the rest of the office"
Write-Line '  ----------------------------------------------------------'
Write-Line ''

# ────────────────────────────────────────────── 1. is anything listening?
$listeners = @(Get-NetTCPConnection -State Listen -LocalPort $Port |
    Select-Object -ExpandProperty LocalAddress -Unique)

if ($listeners.Count -eq 0) {
    Write-Line "  [ ] Nothing is listening on port $Port right now." 'DarkGray'
    Write-Line "      Start the program first (scripts\start-backend.bat, or the desktop icon)."
    Write-Line ''
} else {
    foreach ($address in $listeners) {
        $meaning = switch ($address) {
            '0.0.0.0' { 'every network card - the other devices can reach it' }
            '127.0.0.1' { 'this machine only - a desktop installation' }
            '::'        { 'every network card, IPv6 and IPv4' }
            default     { "bound to this address alone" }
        }
        Write-Line "  [+] listening on $address - $meaning" 'Green'
    }
    Write-Line ''
    if ($listeners -notcontains '0.0.0.0' -and $listeners -notcontains '::') {
        Write-Line '  [!] The server is bound to the loopback address, so a phone on the' 'Yellow'
        Write-Line '      network will not reach it whatever the firewall says. That is the' 'Yellow'
        Write-Line '      desktop setting (HOST=127.0.0.1); a server installation leaves HOST' 'Yellow'
        Write-Line '      alone, which answers on every interface.' 'Yellow'
        Write-Line ''
    }
}

# ─────────────────────────────────────────────── 2. the addresses to type
$cards = @(Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.PrefixOrigin -ne 'WellKnown' })

Write-Line '  Addresses a device on this network can open:'
if ($cards.Count -eq 0) {
    Write-Line '    (no IPv4 address on this machine - is it on the network at all?)' 'Yellow'
}
foreach ($card in $cards) {
    $kind = switch ($card.PrefixOrigin) {
        'Dhcp' { 'from the router' }
        'Manual' { 'set by hand' }
        default { $card.PrefixOrigin }
    }
    Write-Line "    http://$($card.IPAddress):$Port   ($($card.InterfaceAlias), $kind)" 'Cyan'
}
Write-Line ''
Write-Line '    Local address, on this machine: http://localhost:' + $Port
Write-Line ''

# ────────────────────────────────────────────────────────── 3. the firewall
$rule = Get-NetFirewallRule -DisplayGroup 'KAYAN ERP' |
    Where-Object { $_.Enabled -eq 'True' } | Select-Object -First 1

$portOpen = $false
if ($rule) {
    $filters = @($rule | Get-NetFirewallPortFilter)
    $portOpen = $true
    Write-Line "  [+] A firewall rule for KAYAN is on: '$($rule.Name)'." 'Green'
} else {
    # Anything already letting this port through by another rule counts too:
    # a server that has been set up by hand should not be told to do it again.
    $byPort = @(Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow |
        ForEach-Object { $_ | Get-NetFirewallPortFilter } |
        Where-Object { $_.LocalPort -eq "$Port" })
    if ($byPort.Count -gt 0) {
        $portOpen = $true
        Write-Line "  [+] Port $Port is already allowed by another rule." 'Green'
    } else {
        Write-Line "  [ ] No firewall rule allows the inbound port $Port." 'Yellow'
        Write-Line '      Without one, this machine answers the office only when the profile' 'Yellow'
        Write-Line '      it is on is set to Private - and a network that changed name today' 'Yellow'
        Write-Line '      is Public again, quietly.' 'Yellow'
        Write-Line ''
        $command = "New-NetFirewallRule -DisplayName 'KAYAN ERP ($Port)' -Group 'KAYAN ERP' " +
            '-Direction Inbound -Action Allow -Protocol TCP -LocalPort ' + $Port +
            " -Profile Private,Domain"
        Write-Line '      To open it, run this once in an elevated PowerShell:' 'Gray'
        Write-Line "        $command" 'Gray'
        Write-Line '      or run:  scripts\lan-access.ps1 -OpenFirewall' 'Gray'
        if ($OpenFirewall) {
            Write-Line ''
            if (-not $IsAdmin) {
                Write-Line '  [!] -OpenFirewall needs the elevated PowerShell; the command above is' 'Red'
                Write-Line '      the whole of it - nothing was changed.' 'Red'
            } else {
                New-NetFirewallRule -DisplayName "KAYAN ERP ($Port)" -Group 'KAYAN ERP' `
                    -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port `
                    -Profile Private,Domain | Out-Null
                Write-Line "  [+] Rule 'KAYAN ERP ($Port)' created: the port is open on the" 'Green'
                Write-Line '      private and domain profiles. Public networks are still shut -' 'Green'
                Write-Line '      that is the network in the café, and it should stay shut.' 'Green'
            }
        }
    }
}
Write-Line ''

# ────────────────────────────────────────────────── 4. what a browser sees
Write-Line '  Two more things decide whether a device can sign in:'
Write-Line '    - the server answers on every interface (HOST unset, or 0.0.0.0);'
Write-Line '    - the origin of the page is allowed by CORS. Private addresses - 192.168/,'
Write-Line '      10., 172.16-31., *.local - are allowed already, so a LAN visit needs'
Write-Line '      nothing. A name or a port outside those ranges goes in CORS_ORIGINS.'
Write-Line ''

if ($CheckHttps) {
    Write-Line '  HTTPS, from outside the building:'
    $trust = $env:TRUST_PROXY
    if ([string]::IsNullOrWhiteSpace($trust)) {
        Write-Line '  [!] TRUST_PROXY is not set. Behind a TLS proxy every visitor then looks' 'Yellow'
        Write-Line '      like the proxy to the sign-in rate limiter, and the links the program' 'Yellow'
        Write-Line '      builds come out on the internal address. Set it to loopback when the' 'Yellow'
        Write-Line '      proxy runs on this machine, or true when only the proxy can reach it.' 'Yellow'
    } else {
        Write-Line "  [+] TRUST_PROXY=$trust - forwarded addresses and the HTTPS flag are believed." 'Green'
    }
    if ($portOpen) {
        Write-Line ''
        Write-Line "  [ ] Check from outside that port $Port is NOT reachable directly: only 443" 'Yellow'
        Write-Line '      should answer on the public side, and the proxy is what turns to it.' 'Yellow'
    }
    Write-Line '      The procedure and the proxy files: docs\NETWORK_ACCESS.md.'
    Write-Line ''
}

Write-Line '  Done. Nothing on this machine was changed unless -OpenFirewall said so.'
Write-Line ''
