# Poll the summed working set of all running ilandc processes and record the peak.
#
# Why polling: Process.PeakWorkingSet64 does not survive process exit (verified
# 2026-08-24 -- it reads empty once the child has gone), so the high-water mark
# has to be sampled while the process is alive.
#
# Summing across ALL ilandc processes is deliberate. With one instance it gives
# the per-instance peak; with N concurrent instances it gives the node total,
# which is the number that has to fit inside a Derecho node's 235 GB.
#
# Like PBS's resources_used.mem this is a polled maximum, so a spike shorter than
# the interval can be missed.
param(
    [Parameter(Mandatory=$true)][string]$OutFile,
    [int]$IntervalSec = 2,
    [int]$WaitForStartSec = 120,
    [string]$ProcName = "ilandc",
    [string]$TraceFile = ""
)

$max = 0L
$waited = 0
$t0 = $null
if ($TraceFile) { Set-Content -Path $TraceFile -Value "elapsed_s,bytes" -Encoding ascii }
while (-not (Get-Process -Name $ProcName -ErrorAction SilentlyContinue) -and $waited -lt $WaitForStartSec) {
    Start-Sleep -Seconds 1
    $waited++
}

while ($true) {
    $procs = Get-Process -Name $ProcName -ErrorAction SilentlyContinue
    if (-not $procs) { break }
    $sum = ($procs | Measure-Object -Property WorkingSet64 -Sum).Sum
    if ($sum -gt $max) { $max = $sum }
    if ($TraceFile) {
        if ($null -eq $t0) { $t0 = Get-Date }
        $el = [int]((Get-Date) - $t0).TotalSeconds
        Add-Content -Path $TraceFile -Value "$el,$sum" -Encoding ascii
    }
    Start-Sleep -Seconds $IntervalSec
}

# plain bytes, no thousands separators -- this gets parsed
Set-Content -Path $OutFile -Value $max -Encoding ascii
