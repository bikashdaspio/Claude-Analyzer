# ═══════════════════════════════════════════════════════════════════════════════
# Parallel Processing Functions
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent multiple sourcing
if ($script:_PARALLEL_LOADED) { return }
$script:_PARALLEL_LOADED = $true

# Initialize parallel processing
function Initialize-Parallel {
    $script:PARALLEL_RESULTS_DIR = Join-Path $script:STATE_DIR "parallel_results_$PID"
    if (-not (Test-Path $script:PARALLEL_RESULTS_DIR)) {
        New-Item -ItemType Directory -Path $script:PARALLEL_RESULTS_DIR -Force | Out-Null
    }
    $script:PARALLEL_JOBS_LIST = [System.Collections.ArrayList]::new()
}

# Cleanup parallel processing
function Remove-ParallelResources {
    if ($script:PARALLEL_RESULTS_DIR -and (Test-Path $script:PARALLEL_RESULTS_DIR)) {
        Remove-Item -Path $script:PARALLEL_RESULTS_DIR -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Collect all pending results from the results directory
function Get-AllPendingResults {
    $resultFiles = Get-ChildItem -Path $script:PARALLEL_RESULTS_DIR -Filter "result_*" -ErrorAction SilentlyContinue

    foreach ($rf in $resultFiles) {
        $content = Get-Content $rf.FullName -ErrorAction SilentlyContinue
        if ($content) {
            $parts = $content -split ' ', 3
            $status = $parts[0]

            switch ($status) {
                "success" { $script:SUCCESS_COUNT++ }
                "failed"  { $script:FAILED_COUNT++ }
                "skipped" { $script:SKIPPED_COUNT++ }
            }
            Remove-Item $rf.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

# Wait for a slot to become available when running at max capacity
function Wait-ForSlot {
    while ($script:PARALLEL_JOBS_LIST.Count -ge $script:PARALLEL_JOBS) {
        # Check for completed jobs
        $newJobs = [System.Collections.ArrayList]::new()
        foreach ($job in $script:PARALLEL_JOBS_LIST) {
            if ($job.State -eq 'Running') {
                [void]$newJobs.Add($job)
            } else {
                # Job completed, receive output and remove
                Receive-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
        }
        $script:PARALLEL_JOBS_LIST = $newJobs

        # Collect any pending results
        Get-AllPendingResults

        # Still at capacity, wait a bit
        if ($script:PARALLEL_JOBS_LIST.Count -ge $script:PARALLEL_JOBS) {
            Start-Sleep -Seconds 1
        }
    }
}

# Wait for all parallel jobs to complete
function Wait-ForAllJobs {
    Write-LogInfo "Waiting for $($script:PARALLEL_JOBS_LIST.Count) remaining jobs to complete..."
    foreach ($job in $script:PARALLEL_JOBS_LIST) {
        $null = Wait-Job -Job $job -ErrorAction SilentlyContinue
        Receive-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
    $script:PARALLEL_JOBS_LIST = [System.Collections.ArrayList]::new()

    # Collect all remaining results
    Get-AllPendingResults
}

# Launch a module analysis as a background job
function Start-ParallelJob {
    param(
        [string]$Name,
        [string]$Parent,
        [string]$Complexity
    )

    $resultFile = Join-Path $script:PARALLEL_RESULTS_DIR "result_$(Get-Random)_$(Get-Date -Format 'HHmmssffff')"

    $job = Start-Job -ScriptBlock {
        param($ScriptDir, $Name, $Parent, $Complexity, $ResultFile, $LogDir, $ModuleStructureFile, $FailedFile, $DryRun, $NoTimeout, $CustomTimeout, $TimeoutLow, $TimeoutMedium, $TimeoutHigh)

        # Set up display name and log file
        if ($Parent) {
            $displayName = "$Parent/$Name"
            $logFile = Join-Path $LogDir "${Parent}_${Name}.log"
        } else {
            $displayName = $Name
            $logFile = Join-Path $LogDir "${Name}.log"
        }

        # Check if already analyzed
        if ($Parent) {
            $result = & jq -r --arg parent $Parent --arg name $Name '
                .modules[] | select(.name == $parent) | .subModules[] | select(.name == $name) | .analyzed // false
            ' $ModuleStructureFile 2>$null
        } else {
            $result = & jq -r --arg name $Name '
                .modules[] | select(.name == $name) | .analyzed // false
            ' $ModuleStructureFile 2>$null
        }

        if ($result -eq "true") {
            "skipped $Name $Parent" | Out-File -FilePath $ResultFile -Encoding UTF8
            Write-Host "[SKIP] $displayName (already analyzed)"
            return
        }

        # Get timeout
        $timeoutSeconds = 0
        if (-not $NoTimeout) {
            if ($CustomTimeout -gt 0) {
                $timeoutSeconds = $CustomTimeout
            } else {
                switch ($Complexity) {
                    "low"    { $timeoutSeconds = $TimeoutLow }
                    "medium" { $timeoutSeconds = $TimeoutMedium }
                    "high"   { $timeoutSeconds = $TimeoutHigh }
                    default  { $timeoutSeconds = $TimeoutMedium }
                }
            }
        }

        $timeoutMsg = if ($timeoutSeconds -eq 0) { "no timeout" } else { "timeout: ${timeoutSeconds}s" }
        Write-Host "[START] $displayName (complexity: $Complexity, $timeoutMsg)"

        if ($DryRun) {
            Write-Host "[DRY-RUN] Would analyze: $displayName"
            "success $Name $Parent" | Out-File -FilePath $ResultFile -Encoding UTF8
            return
        }

        # Run claude analysis
        try {
            $claudeArgs = @(
                "--dangerously-skip-permissions",
                "--print",
                "--output-format", "text",
                "/analyze $displayName"
            )

            if ($timeoutSeconds -eq 0) {
                $output = & claude @claudeArgs 2>&1
                $exitCode = $LASTEXITCODE
            } else {
                $processInfo = New-Object System.Diagnostics.ProcessStartInfo
                $processInfo.FileName = "claude"
                $processInfo.Arguments = $claudeArgs -join " "
                $processInfo.RedirectStandardOutput = $true
                $processInfo.RedirectStandardError = $true
                $processInfo.UseShellExecute = $false
                $processInfo.CreateNoWindow = $true

                $process = New-Object System.Diagnostics.Process
                $process.StartInfo = $processInfo
                $process.Start() | Out-Null

                $completed = $process.WaitForExit($timeoutSeconds * 1000)

                if (-not $completed) {
                    $process.Kill()
                    $process.WaitForExit()
                    "TIMEOUT after ${timeoutSeconds}s" | Out-File -FilePath $logFile -Encoding UTF8
                    if ($Parent) {
                        "${Name}|${Parent}|${Complexity}" | Add-Content -Path $FailedFile
                    } else {
                        "${Name}||${Complexity}" | Add-Content -Path $FailedFile
                    }
                    "failed $Name $Parent" | Out-File -FilePath $ResultFile -Encoding UTF8
                    Write-Host "[FAIL] $displayName (timeout)"
                    return
                }

                $output = $process.StandardOutput.ReadToEnd()
                $exitCode = $process.ExitCode
            }

            $output | Out-File -FilePath $logFile -Encoding UTF8

            if ($exitCode -eq 0) {
                # Mark as analyzed
                $tmpFile = "$ModuleStructureFile.tmp.$(Get-Random)"
                if ($Parent) {
                    $jqScript = ".modules = [.modules[] | if .name == `"$Parent`" then .subModules = [.subModules[] | if .name == `"$Name`" then .analyzed = true else . end] else . end]"
                } else {
                    $jqScript = ".modules = [.modules[] | if .name == `"$Name`" then .analyzed = true else . end]"
                }
                & jq $jqScript $ModuleStructureFile | Out-File -FilePath $tmpFile -Encoding UTF8 -NoNewline
                Move-Item -Path $tmpFile -Destination $ModuleStructureFile -Force

                "success $Name $Parent" | Out-File -FilePath $ResultFile -Encoding UTF8
                Write-Host "[DONE] $displayName"
            } else {
                if ($Parent) {
                    "${Name}|${Parent}|${Complexity}" | Add-Content -Path $FailedFile
                } else {
                    "${Name}||${Complexity}" | Add-Content -Path $FailedFile
                }
                "failed $Name $Parent" | Out-File -FilePath $ResultFile -Encoding UTF8
                Write-Host "[FAIL] $displayName (exit code: $exitCode)"
            }
        } catch {
            if ($Parent) {
                "${Name}|${Parent}|${Complexity}" | Add-Content -Path $FailedFile
            } else {
                "${Name}||${Complexity}" | Add-Content -Path $FailedFile
            }
            "failed $Name $Parent" | Out-File -FilePath $ResultFile -Encoding UTF8
            Write-Host "[FAIL] $displayName ($_)"
        }
    } -ArgumentList $script:SCRIPT_DIR, $Name, $Parent, $Complexity, $resultFile, $script:LOG_DIR, $script:MODULE_STRUCTURE_FILE, $script:FAILED_FILE, $script:DRY_RUN, $script:NO_TIMEOUT, $script:CUSTOM_TIMEOUT, $script:TIMEOUT_LOW, $script:TIMEOUT_MEDIUM, $script:TIMEOUT_HIGH

    [void]$script:PARALLEL_JOBS_LIST.Add($job)
    $displayPath = if ($Parent) { "$Parent/$Name" } else { $Name }
    Write-LogDebug "Launched job $($job.Id) for $displayPath"
}

# Parallel processing main loop
function Invoke-MainLoopParallel {
    param([string]$QueueSource)

    Write-LogInfo "Running in parallel mode with $script:PARALLEL_JOBS concurrent jobs"

    # Initialize parallel processing
    Initialize-Parallel

    $jobsLaunched = 0
    $lines = Get-Content $QueueSource -ErrorAction SilentlyContinue

    foreach ($line in $lines) {
        # Skip comments and empty lines
        if ($line -match "^#" -or [string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        # Parse: name|parent|complexity
        $parts = $line -split '\|'
        $name = $parts[0]
        $parent = if ($parts.Count -gt 1) { $parts[1] } else { "" }
        $complexity = if ($parts.Count -gt 2) { $parts[2] } else { "medium" }

        # Single module mode
        if ($script:SINGLE_MODULE) {
            $fullName = if ($parent) { "$parent/$name" } else { $name }
            if ($fullName -ne $script:SINGLE_MODULE -and $name -ne $script:SINGLE_MODULE) {
                continue
            }
        }

        # Skip already analyzed in the parent process to avoid launching unnecessary jobs
        if (Test-ModuleAnalyzed -ModuleName $name -ParentModule $parent) {
            $displayPath = if ($parent) { "$parent/$name" } else { $name }
            Write-LogInfo "[SKIP] $displayPath (already analyzed)"
            $script:SKIPPED_COUNT++
            continue
        }

        # Wait for a slot if at capacity
        Wait-ForSlot

        # Launch the job
        Start-ParallelJob -Name $name -Parent $parent -Complexity $complexity
        $jobsLaunched++

        # Small delay between launches to prevent overwhelming the system
        if ($script:DELAY_SECONDS -gt 0 -and -not $script:DRY_RUN) {
            Start-Sleep -Seconds $script:DELAY_SECONDS
        }
    }

    # Wait for all remaining jobs
    if ($script:PARALLEL_JOBS_LIST.Count -gt 0) {
        Wait-ForAllJobs
    }

    Write-LogInfo "Parallel processing complete. Launched $jobsLaunched jobs."

    # Cleanup
    Remove-ParallelResources
}
