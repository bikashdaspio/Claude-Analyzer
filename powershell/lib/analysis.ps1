# ═══════════════════════════════════════════════════════════════════════════════
# Analysis Functions - Core module analysis logic
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent multiple sourcing
if ($script:_ANALYSIS_LOADED) { return }
$script:_ANALYSIS_LOADED = $true

# Get timeout based on complexity
# Returns 0 if no timeout should be applied
function Get-Timeout {
    param([string]$Complexity)

    # No timeout mode
    if ($script:NO_TIMEOUT) {
        return 0
    }

    # Custom timeout override
    if ($script:CUSTOM_TIMEOUT -gt 0) {
        return $script:CUSTOM_TIMEOUT
    }

    # Complexity-based timeout
    switch ($Complexity) {
        "low"    { return $script:TIMEOUT_LOW }
        "medium" { return $script:TIMEOUT_MEDIUM }
        "high"   { return $script:TIMEOUT_HIGH }
        default  { return $script:TIMEOUT_MEDIUM }
    }
}

# Run claude analysis for a module
# Usage: Invoke-ClaudeAnalysis "ModuleName" "log_file" "timeout_seconds"
function Invoke-ClaudeAnalysis {
    param(
        [Parameter(Mandatory=$true)][string]$ModuleName,
        [Parameter(Mandatory=$true)][string]$LogFile,
        [int]$TimeoutSeconds
    )

    $timeoutMsg = "no timeout"
    if ($TimeoutSeconds -gt 0) {
        $timeoutMsg = "timeout: ${TimeoutSeconds}s"
    }
    Write-LogDebug "Running claude analysis for: $ModuleName ($timeoutMsg)"

    if ($script:DRY_RUN) {
        Write-LogInfo "[DRY-RUN] Would analyze: $ModuleName"
        return $true
    }

    try {
        $claudeArgs = @(
            "--dangerously-skip-permissions",
            "--print",
            "--output-format", "text",
            "/analyze $ModuleName"
        )

        if ($TimeoutSeconds -eq 0) {
            # No timeout - run indefinitely
            $output = & claude @claudeArgs 2>&1
            $exitCode = $LASTEXITCODE
        } else {
            # Run with timeout using Start-Process
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

            $completed = $process.WaitForExit($TimeoutSeconds * 1000)

            if (-not $completed) {
                $process.Kill()
                $process.WaitForExit()
                Write-LogError "Timeout analyzing $ModuleName after ${TimeoutSeconds}s"
                "TIMEOUT after ${TimeoutSeconds}s" | Out-File -FilePath $LogFile -Encoding UTF8
                return $false
            }

            $output = $process.StandardOutput.ReadToEnd()
            $errorOutput = $process.StandardError.ReadToEnd()
            $exitCode = $process.ExitCode

            if ($errorOutput) {
                $output += "`n$errorOutput"
            }
        }

        # Write output to log file
        $output | Out-File -FilePath $LogFile -Encoding UTF8

        if ($exitCode -eq 0) {
            return $true
        } else {
            Write-LogError "Claude analysis failed for $ModuleName (exit code: $exitCode)"
            return $false
        }
    } catch {
        Write-LogError "Claude analysis failed for $ModuleName : $_"
        "ERROR: $_" | Out-File -FilePath $LogFile -Encoding UTF8
        return $false
    }
}

# Analyze a single module
# Usage: Invoke-SingleModuleAnalysis "ModuleName" "ParentModule" "complexity"
function Invoke-SingleModuleAnalysis {
    param(
        [Parameter(Mandatory=$true)][string]$ModuleName,
        [string]$ParentModule = "",
        [string]$Complexity = "medium"
    )

    if ($ParentModule) {
        $displayName = "$ParentModule/$ModuleName"
        $logFile = Join-Path $script:LOG_DIR "${ParentModule}_${ModuleName}.log"
    } else {
        $displayName = $ModuleName
        $logFile = Join-Path $script:LOG_DIR "${ModuleName}.log"
    }

    # Check if already analyzed
    if (Test-ModuleAnalyzed -ModuleName $ModuleName -ParentModule $ParentModule) {
        Write-LogInfo "Skipping $displayName (already analyzed)"
        $script:SKIPPED_COUNT++
        return $true
    }

    $timeoutSeconds = Get-Timeout -Complexity $Complexity

    Write-Host ""
    Write-LogInfo "Analyzing: $displayName (complexity: $Complexity, timeout: ${timeoutSeconds}s)"

    # Run the analysis
    if (Invoke-ClaudeAnalysis -ModuleName $displayName -LogFile $logFile -TimeoutSeconds $timeoutSeconds) {
        # Mark as analyzed on success
        Set-ModuleAnalyzed -ModuleName $ModuleName -ParentModule $ParentModule
        Write-LogSuccess "Completed: $displayName"
        $script:SUCCESS_COUNT++
        return $true
    } else {
        # Add to failed list
        if ($ParentModule) {
            "${ModuleName}|${ParentModule}|${Complexity}" | Add-Content -Path $script:FAILED_FILE
        } else {
            "${ModuleName}||${Complexity}" | Add-Content -Path $script:FAILED_FILE
        }
        Write-LogError "Failed: $displayName (see $logFile)"
        $script:FAILED_COUNT++
        return $false
    }
}

# Sequential processing main loop
function Invoke-MainLoopSequential {
    param([string]$QueueSource)

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

        Invoke-SingleModuleAnalysis -ModuleName $name -ParentModule $parent -Complexity $complexity

        # Delay between modules
        if ($script:DELAY_SECONDS -gt 0 -and -not $script:DRY_RUN) {
            Start-Sleep -Seconds $script:DELAY_SECONDS
        }
    }
}

# Main analysis loop dispatcher
function Invoke-MainLoop {
    $queueSource = $script:QUEUE_FILE

    if ($script:RETRY_FAILED) {
        if (-not (Test-Path $script:FAILED_FILE) -or (Get-Item $script:FAILED_FILE).Length -eq 0) {
            Write-LogInfo "No failed modules to retry"
            return
        }
        $queueSource = $script:FAILED_FILE
        # Read failed modules and clear the file
        $failedModules = Get-Content $script:FAILED_FILE
        Clear-Content $script:FAILED_FILE

        foreach ($line in $failedModules) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split '\|'
            $name = $parts[0]
            $parent = if ($parts.Count -gt 1) { $parts[1] } else { "" }
            $complexity = if ($parts.Count -gt 2) { $parts[2] } else { "medium" }

            Invoke-SingleModuleAnalysis -ModuleName $name -ParentModule $parent -Complexity $complexity

            # Delay between modules
            if ($script:DELAY_SECONDS -gt 0 -and -not $script:DRY_RUN) {
                Start-Sleep -Seconds $script:DELAY_SECONDS
            }
        }
        return
    }

    # Check if running in parallel mode
    if ($script:PARALLEL_JOBS -gt 1) {
        Invoke-MainLoopParallel -QueueSource $queueSource
    } else {
        Invoke-MainLoopSequential -QueueSource $queueSource
    }
}
