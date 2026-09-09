<#
.SYNOPSIS
	Run the action sample as two operating-system processes and compare what
	each of them ended up believing.

.DESCRIPTION
	Everything else about this engine's networking is checked with two runtimes
	inside one process, which checks the rules and never checks that bytes
	cross. This launches an authority and a client as separate processes with an
	ENet connection between them, waits for both, and fails unless both exited
	zero, neither reported a fault, and the two ended on the same reading of the
	same character.

	It writes artifacts/gates/<TaskId>/multiplayer-sample.json, which
	test/integration/test_network_two_processes.gd reads.

.PARAMETER TaskId
	Which receipt directory to write into. F6.6 by default, since that is the
	task this exists for.

.PARAMETER Port
	Where the authority listens. Change it if something else already has it.
#>
[CmdletBinding()]
param(
	[string] $TaskId = 'F6.6',
	[int] $Port = 47921,
	[int] $TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = Split-Path -Parent $PSScriptRoot
$godot = $env:GAS_ENGINE_GODOT
if (-not $godot) {
	$godot = 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
}
if (-not (Test-Path -LiteralPath $godot)) {
	throw "no Godot at $godot; set GAS_ENGINE_GODOT to where yours lives"
}

$receipts = Join-Path $repo "artifacts/gates/$TaskId"
$null = New-Item -ItemType Directory -Force -Path $receipts
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("gas_engine_mp_" + [System.Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Force -Path $work

$serverOut = Join-Path $work 'server.json'
$clientOut = Join-Path $work 'client.json'
$serverLog = Join-Path $work 'server.log'
$clientLog = Join-Path $work 'client.log'

# `Flags` rather than `Args`: $args is one of PowerShell's own automatic
# variables, and a parameter by that name is silently the empty one instead of
# what the caller passed - which reaches Godot as a run with no arguments and
# reads as the sample refusing its own command line.
function Start-Half {
	param([string] $Script, [string[]] $Flags, [string] $Log)
	$all = @(
		'--headless', '--path', $repo, '-s', $Script, '--'
	) + $Flags
	return Start-Process -FilePath $godot -ArgumentList $all -PassThru -NoNewWindow `
		-RedirectStandardOutput $Log -RedirectStandardError "$Log.err"
}

Write-Host "=== two processes, one wire ==="
Write-Host "authority: port $Port"

$server = Start-Half `
	-Script 'res://examples/action_sample/network/server_main.gd' `
	-Flags @('--server', "--port=$Port", '--automation', "--out=$serverOut") `
	-Log $serverLog

# A moment for the listener, so the client's first attempt is not the one that
# fails: ENet answers a connection to a port nobody is on with a refusal, and
# the sample would report a broken handshake for a race in this script.
Start-Sleep -Milliseconds 1500

$client = Start-Half `
	-Script 'res://examples/action_sample/network/client_main.gd' `
	-Flags @("--client=127.0.0.1:$Port", '--automation', "--out=$clientOut") `
	-Log $clientLog

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$timedOut = $false
foreach ($half in @($client, $server)) {
	$left = [int]($deadline - (Get-Date)).TotalSeconds
	if ($left -lt 1) { $left = 1 }
	if (-not $half.WaitForExit($left * 1000)) {
		$timedOut = $true
		try { $half.Kill() } catch { }
	}
}

function Read-Half {
	param([string] $Path)
	if (-not (Test-Path -LiteralPath $Path)) { return $null }
	return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

$serverSaid = Read-Half $serverOut
$clientSaid = Read-Half $clientOut

$faults = @()
if ($timedOut) { $faults += 'a process had to be killed at the timeout' }
if ($server.ExitCode -ne 0) { $faults += "the authority exited $($server.ExitCode)" }
if ($client.ExitCode -ne 0) { $faults += "the client exited $($client.ExitCode)" }
if ($null -eq $serverSaid) { $faults += 'the authority wrote no receipt' }
if ($null -eq $clientSaid) { $faults += 'the client wrote no receipt' }
if ($serverSaid -and $serverSaid.fault) { $faults += "authority: $($serverSaid.fault)" }
if ($clientSaid -and $clientSaid.fault) { $faults += "client: $($clientSaid.fault)" }
if ($serverSaid -and $clientSaid -and ($serverSaid.state -ne $clientSaid.state)) {
	$faults += 'the two processes ended on different readings of the character'
}

$verdict = if ($faults.Count -eq 0) { 'PASS' } else { 'FAIL' }
$receipt = [ordered]@{
	verdict      = $verdict
	port         = $Port
	server_exit  = $server.ExitCode
	client_exit  = $client.ExitCode
	server_steps = if ($serverSaid) { $serverSaid.steps } else { @() }
	client_steps = if ($clientSaid) { $clientSaid.steps } else { @() }
	state        = if ($clientSaid) { $clientSaid.state } else { '' }
	faults       = $faults
}
$receiptPath = Join-Path $receipts 'multiplayer-sample.json'
$receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $receiptPath -Encoding utf8

Write-Host ''
Write-Host '--- authority ---'
if (Test-Path -LiteralPath $serverLog) { Get-Content -LiteralPath $serverLog | Select-Object -Last 40 }
Write-Host '--- client ---'
if (Test-Path -LiteralPath $clientLog) { Get-Content -LiteralPath $clientLog | Select-Object -Last 40 }
Write-Host ''

foreach ($fault in $faults) { Write-Host "FAULT: $fault" }
Write-Host "receipt: $receiptPath"

# And then the test that reads it. Here rather than in the headless runner,
# because that runner reads test/unit and two Godot processes launched from
# inside a third is not a thing to do on every suite run.
Write-Host ''
Write-Host '--- what the receipt says it was ---'
$suiteLog = Join-Path $work 'suite.log'
$suite = Start-Process -FilePath $godot -PassThru -NoNewWindow -Wait `
	-ArgumentList @(
		'--headless', '--path', $repo, '-s', 'addons/gut/gut_cmdln.gd',
		'-gdir=res://test/integration', '-ginclude_subdirs', '-gexit'
	) -RedirectStandardOutput $suiteLog -RedirectStandardError "$suiteLog.err"
$suiteSaid = if (Test-Path -LiteralPath $suiteLog) { Get-Content -LiteralPath $suiteLog -Raw } else { '' }
if ($suiteSaid) { $suiteSaid -split "`n" | Select-Object -Last 30 }

# Three questions rather than one. GUT exits zero when it ran nothing at all -
# a script it could not parse is "ignored", not failed - so a run that found no
# tests would otherwise be reported as a passing gate over a suite that never
# existed.
$suiteFailed = ($suite.ExitCode -ne 0) `
	-or ($suiteSaid -notmatch 'All tests passed') `
	-or ($suiteSaid -match 'Nothing was run')
# The documented workflow rewrites project.godot on a driven run; putting it
# back is part of the run rather than something to remember afterwards.
& git -C $repo checkout -- project.godot 2>$null

if ($suiteFailed) {
	$verdict = 'FAIL'
	Write-Host 'FAULT: the integration suite refused the receipt'
}
Write-Host "GAS_ENGINE_MULTIPLAYER_SAMPLE: $verdict"

Remove-Item -Recurse -Force -LiteralPath $work -ErrorAction SilentlyContinue
if ($verdict -ne 'PASS') { exit 1 }
exit 0
