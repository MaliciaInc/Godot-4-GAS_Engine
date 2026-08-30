#Requires -Version 7.0

# Integral verification runner for Arhalies GAS, step 1.5 of the Phase 1 plan.
#
# Every execution is synchronous. Nothing here starts a job, a background task
# or a detached process, and no process is left orphaned: a stage that exceeds
# its timeout has its whole tree killed before the run continues.
#
# Override 2 keeps the Godot executable out of this script. Stages 3 and 4 of
# the canonical order - headless import/parse and the GUT suite - are run by the
# implementer through the Godot MCP servers, which deposit their verdict in the
# same receipt this script writes. Those verdicts are READ here and a missing or
# failing one stops the run, so a Full pass cannot be claimed while the two
# engine stages were never executed.
#
# Usage:
#   pwsh -File tooling/verify.ps1 -TaskId T3
#
# Exit codes follow section 9.1: 0 pass, non-zero otherwise. The first failing
# stage stops the run and its exit code is propagated verbatim.

[CmdletBinding()]
param(
    [string] $TaskId = 'full',
    [switch] $SkipEngineStages
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$GateRoot = Join-Path $RepoRoot 'tooling/gates'
$ReceiptRoot = Join-Path $RepoRoot ('artifacts/gates/' + $TaskId)
$PythonExe = 'python'

$PassBanner = 'ARHALIES_GAS_VERIFY_PASS'
$ResultPrefix = 'RESULT:'
$PassWord = 'PASS'

$EngineEvidence = [ordered]@{
    'godot-import' = 'mcp-godot-import.txt'
    'gut-suite'    = 'mcp-gut.txt'
}


function Get-TimeoutSeconds {
    # Stage timeout, overridable per environment. 300 s is the documented default.
    $raw = $env:ARHALIES_VERIFY_TIMEOUT_SECONDS
    if ([string]::IsNullOrWhiteSpace($raw)) { return 300 }
    $parsed = 0
    if (-not [int]::TryParse($raw, [ref] $parsed) -or $parsed -le 0) {
        throw "ARHALIES_VERIFY_TIMEOUT_SECONDS must be a positive integer, got '$raw'"
    }
    return $parsed
}


function Write-Banner {
    param([string] $Text)
    Write-Host ''
    Write-Host ('=' * 72)
    Write-Host $Text
    Write-Host ('=' * 72)
}


function Stop-ProcessTree {
    # Kills the process and every descendant. A stage that timed out must not
    # leave a child holding a file handle the next stage needs.
    param([int] $ProcessId)
    try {
        $null = & taskkill.exe '/T' '/F' '/PID' $ProcessId 2>&1
    }
    catch {
        Write-Host ("could not kill process tree " + $ProcessId + ": " + $_.Exception.Message)
    }
}


function Invoke-CheckedProcess {
    # Runs one stage synchronously, mirroring output to the console and to the
    # receipt, and returns its real exit code. A timeout returns a non-zero code
    # after the process tree is killed.
    param(
        [Parameter(Mandatory)] [string]   $Stage,
        [Parameter(Mandatory)] [string]   $Executable,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter(Mandatory)] [string]   $ReceiptDirectory,
        [int] $TimeoutSeconds = 300
    )

    $commandLine = $Executable + ' ' + ($Arguments -join ' ')
    $startedAt = Get-Date
    Write-Banner ($Stage + '  ->  ' + $commandLine)

    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Executable
    foreach ($argument in $Arguments) { $null = $info.ArgumentList.Add($argument) }
    $info.WorkingDirectory = $RepoRoot
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.UseShellExecute = $false

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $info

    $timedOut = $false
    try {
        $null = $process.Start()
        # Both streams are drained concurrently. Reading one to the end while
        # the other fills its buffer is the classic way to deadlock here.
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            Stop-ProcessTree -ProcessId $process.Id
            $null = $process.WaitForExit(5000)
        }
        $standardOutput = $outTask.GetAwaiter().GetResult()
        $standardError = $errTask.GetAwaiter().GetResult()
        $exitCode = if ($timedOut) { 124 } else { $process.ExitCode }
    }
    finally {
        $process.Dispose()
    }

    $endedAt = Get-Date
    $duration = ($endedAt - $startedAt).TotalSeconds

    if ($standardOutput) { Write-Host $standardOutput.TrimEnd() }
    if ($standardError) { Write-Host $standardError.TrimEnd() }

    $status = if ($timedOut) { 'TIMEOUT' } elseif ($exitCode -eq 0) { $PassWord } else { 'FAIL' }
    $log = @(
        ($ResultPrefix + ' ' + $status),
        ('stage:      ' + $Stage),
        ('command:    ' + $commandLine),
        ('started:    ' + $startedAt.ToUniversalTime().ToString('o')),
        ('ended:      ' + $endedAt.ToUniversalTime().ToString('o')),
        ('duration_s: ' + $duration.ToString('F3')),
        ('exit_code:  ' + $exitCode),
        '',
        '--- stdout ---',
        $standardOutput,
        '--- stderr ---',
        $standardError
    )
    $logPath = Join-Path $ReceiptDirectory ($Stage + '.log')
    # LF joined explicitly, not via an escape: PowerShell's escape character is
    # the backtick, and the magic-string gate's generic scanner reads a backtick
    # as a template-literal quote. Avoiding it keeps this file honestly scannable.
    Set-Content -LiteralPath $logPath -Value ($log -join [string][char]10) -Encoding utf8NoBOM

    Write-Host ($Stage + ': ' + $status + ' (exit ' + $exitCode + ', ' + $duration.ToString('F3') + 's)')
    return $exitCode
}




function Test-EngineEvidence {
    # Stages 3 and 4 are executed through the Godot MCP servers, not here. This
    # reads their verdicts. Absent evidence is a failure, not a skip: a Full run
    # that never touched the engine must not be able to report success.
    param([string] $ReceiptDirectory)

    $allPassed = $true
    foreach ($stage in $EngineEvidence.Keys) {
        $path = Join-Path $ReceiptDirectory $EngineEvidence[$stage]
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Host ($stage + ': MISSING engine evidence at ' + $path)
            $allPassed = $false
            continue
        }
        $first = (Get-Content -LiteralPath $path -TotalCount 1)
        $verdict = ($first -replace [regex]::Escape($ResultPrefix), '').Trim()
        if ($verdict -ne $PassWord) {
            Write-Host ($stage + ': engine evidence reports ' + $verdict)
            $allPassed = $false
            continue
        }
        Write-Host ($stage + ': ' + $PassWord + ' (from ' + $EngineEvidence[$stage] + ')')
    }
    return $allPassed
}


function Get-GateStages {
    # Stages 5 to 8, in the canonical order. The flag names and report paths are
    # NOT spelled here: run_gate.py owns them, next to the gates whose CLI Task 0
    # sealed. Two spellings of one contract drift the first time either side is
    # touched, and nothing reports it - the runner just stops passing an option
    # nobody noticed had been renamed.
    param([string] $ReceiptDirectory)

    $runner = Join-Path $GateRoot 'run_gate.py'
    # The roster comes from run_gate.py, so adding a gate is one edit there
    # rather than two that can disagree.
    $names = & $PythonExe $runner '--list'
    if ($LASTEXITCODE -ne 0 -or -not $names) {
        throw 'could not read the gate roster from run_gate.py'
    }
    return $names | ForEach-Object {
        @{
            Stage = $_
            Arguments = @($runner, $_, $ReceiptDirectory)
        }
    }
}


function Invoke-Verification {
    param([string] $ReceiptDirectory, [int] $TimeoutSeconds)

    # Stage 1. tooling/seal_policy.py owns the seal: it checks that every
    # sealed file is unchanged AND that every file the sealed globs reach is in
    # the seal. The second direction is what a hand-written list could not do,
    # and it is how a new gate module used to sit outside the seal while every
    # hash still matched. Any difference is POLICY_DRIFT and stops the run
    # before a single gate can report a comforting green.
    Write-Banner 'policy seal'
    $seal = @{
        Stage = 'policy-seal'
        Executable = $PythonExe
        Arguments = @('tooling/seal_policy.py')
        ReceiptDirectory = $ReceiptDirectory
        TimeoutSeconds = $TimeoutSeconds
    }
    if ((Invoke-CheckedProcess @seal) -ne 0) { return 2 }

    $stages = @(
        @{ Stage = 'gate-self-tests'
           Arguments = @('-m', 'unittest', 'discover', '-s', 'tooling/gates/tests', '-p', 'test_*.py') },
        # Runs before the gates: no gate can see project.godot losing a setting
        # to the editor's rewrite, or declaring an autoload a clean checkout
        # will not have. Both have happened here.
        @{ Stage = 'project-invariants'
           Arguments = @('tooling/project_invariants.py') }
    ) + (Get-GateStages -ReceiptDirectory $ReceiptDirectory)

    foreach ($stage in $stages) {
        $call = @{
            Stage = $stage.Stage
            Executable = $PythonExe
            Arguments = $stage.Arguments
            ReceiptDirectory = $ReceiptDirectory
            TimeoutSeconds = $TimeoutSeconds
        }
        $code = Invoke-CheckedProcess @call
        if ($code -ne 0) { return $code }
    }

    if (-not $SkipEngineStages) {
        Write-Banner 'engine stages (Godot MCP, Override 2)'
        if (-not (Test-EngineEvidence -ReceiptDirectory $ReceiptDirectory)) { return 3 }
    }
    else {
        Write-Host 'engine stages SKIPPED by request; this run is not a Full verification'
    }

    $diff = @{
        Stage = 'git-diff-check'
        Executable = 'git'
        Arguments = @('diff', '--check')
        ReceiptDirectory = $ReceiptDirectory
        TimeoutSeconds = $TimeoutSeconds
    }
    return Invoke-CheckedProcess @diff
}


$null = New-Item -ItemType Directory -Force -Path $ReceiptRoot
$timeout = Get-TimeoutSeconds
Write-Host ('task: ' + $TaskId + '  receipt: ' + $ReceiptRoot + '  timeout: ' + $timeout + 's')

$result = Invoke-Verification -ReceiptDirectory $ReceiptRoot -TimeoutSeconds $timeout
if ($result -eq 0) {
    Write-Banner $PassBanner
}
else {
    Write-Banner ('ARHALIES_GAS_VERIFY_FAIL (exit ' + $result + ')')
}
exit $result
