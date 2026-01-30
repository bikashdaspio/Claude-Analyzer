# ═══════════════════════════════════════════════════════════════════════════════
# Markdown Validation Phase
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent multiple sourcing
if ($script:_VALIDATION_LOADED) { return }
$script:_VALIDATION_LOADED = $true

# Find all markdown files in Documents directory
function Find-MarkdownFiles {
    if (-not (Test-Path $script:DOCS_DIR)) {
        Write-LogWarn "Documents directory not found: $script:DOCS_DIR"
        return @()
    }

    Get-ChildItem -Path $script:DOCS_DIR -Filter "*.md" -Recurse -File |
        Where-Object { $_.Name -notmatch "\.backup\.md$" } |
        Sort-Object FullName |
        Select-Object -ExpandProperty FullName
}

# Run markdown validation for a single file
# Usage: Invoke-Validation "file_path" "log_file"
function Invoke-Validation {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string]$LogFile
    )

    Write-LogDebug "Running markdown validation for: $FilePath"

    if ($script:DRY_RUN) {
        Write-LogInfo "[DRY-RUN] Would validate: $FilePath"
        return $true
    }

    try {
        $claudeArgs = @(
            "--dangerously-skip-permissions",
            "--print",
            "--output-format", "text",
            "/validate-markdown $FilePath --auto-fix"
        )

        $output = & claude @claudeArgs 2>&1
        $exitCode = $LASTEXITCODE

        $output | Out-File -FilePath $LogFile -Encoding UTF8

        if ($exitCode -eq 0) {
            return $true
        } else {
            Write-LogError "Validation failed for $FilePath (exit code: $exitCode)"
            return $false
        }
    } catch {
        Write-LogError "Validation failed for $FilePath : $_"
        "ERROR: $_" | Out-File -FilePath $LogFile -Encoding UTF8
        return $false
    }
}

# Launch validation as a background job
function Start-ValidationJob {
    param([string]$FilePath)

    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $resultFile = Join-Path $script:PARALLEL_RESULTS_DIR "result_val_$(Get-Random)_$(Get-Date -Format 'HHmmssffff')"
    $logFile = Join-Path $script:LOG_DIR "validation_${fileName}.log"

    $job = Start-Job -ScriptBlock {
        param($FilePath, $ResultFile, $LogFile, $DryRun)

        $fileName = [System.IO.Path]::GetFileName($FilePath)

        Write-Host "[START] Validating: $fileName"

        if ($DryRun) {
            Write-Host "[DRY-RUN] Would validate: $fileName"
            "success $FilePath" | Out-File -FilePath $ResultFile -Encoding UTF8
            return
        }

        try {
            $claudeArgs = @(
                "--dangerously-skip-permissions",
                "--print",
                "--output-format", "text",
                "/validate-markdown $FilePath --auto-fix"
            )

            $output = & claude @claudeArgs 2>&1
            $exitCode = $LASTEXITCODE

            $output | Out-File -FilePath $LogFile -Encoding UTF8

            if ($exitCode -eq 0) {
                "success $FilePath" | Out-File -FilePath $ResultFile -Encoding UTF8
                Write-Host "[DONE] Validated: $fileName"
            } else {
                "failed $FilePath" | Out-File -FilePath $ResultFile -Encoding UTF8
                Write-Host "[FAIL] Validation failed: $fileName"
            }
        } catch {
            "failed $FilePath" | Out-File -FilePath $ResultFile -Encoding UTF8
            Write-Host "[FAIL] Validation failed: $fileName ($_)"
        }
    } -ArgumentList $FilePath, $resultFile, $logFile, $script:DRY_RUN

    [void]$script:PARALLEL_JOBS_LIST.Add($job)
    Write-LogDebug "Launched validation job $($job.Id) for $fileName"
}

# Collect validation results
function Get-ValidationResults {
    $resultFiles = Get-ChildItem -Path $script:PARALLEL_RESULTS_DIR -Filter "result_val_*" -ErrorAction SilentlyContinue

    foreach ($rf in $resultFiles) {
        $content = Get-Content $rf.FullName -ErrorAction SilentlyContinue
        if ($content) {
            $parts = $content -split ' ', 2
            $status = $parts[0]

            switch ($status) {
                "success" { $script:VALIDATION_SUCCESS++ }
                "failed"  { $script:VALIDATION_FAILED++ }
            }
            Remove-Item $rf.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

# Main validation loop (parallel)
function Invoke-ValidationLoopParallel {
    $mdFiles = Find-MarkdownFiles

    if ($mdFiles.Count -eq 0) {
        Write-LogWarn "No markdown files found to validate"
        return
    }

    Write-LogInfo "Found $($mdFiles.Count) markdown files to validate"
    Write-LogInfo "Running validation in parallel with $script:PARALLEL_JOBS concurrent jobs"

    # Initialize parallel processing
    Initialize-Parallel

    $jobsLaunched = 0

    foreach ($filePath in $mdFiles) {
        # Wait for a slot if at capacity
        Wait-ForSlot

        # Launch the job
        Start-ValidationJob -FilePath $filePath
        $jobsLaunched++

        # Small delay between launches
        if ($script:DELAY_SECONDS -gt 0 -and -not $script:DRY_RUN) {
            Start-Sleep -Seconds 1
        }
    }

    # Wait for all remaining jobs
    if ($script:PARALLEL_JOBS_LIST.Count -gt 0) {
        Wait-ForAllJobs
    }

    # Collect any remaining results
    Get-ValidationResults

    Write-LogInfo "Validation complete. Launched $jobsLaunched jobs."

    # Cleanup
    Remove-ParallelResources
}

# Main validation loop (sequential)
function Invoke-ValidationLoopSequential {
    $mdFiles = Find-MarkdownFiles

    if ($mdFiles.Count -eq 0) {
        Write-LogWarn "No markdown files found to validate"
        return
    }

    Write-LogInfo "Found $($mdFiles.Count) markdown files to validate"

    foreach ($filePath in $mdFiles) {
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
        $logFile = Join-Path $script:LOG_DIR "validation_${fileName}.log"

        Write-LogInfo "Validating: $fileName"

        if (Invoke-Validation -FilePath $filePath -LogFile $logFile) {
            Write-LogSuccess "Validated: $fileName"
            $script:VALIDATION_SUCCESS++
        } else {
            Write-LogError "Failed: $fileName (see $logFile)"
            $script:VALIDATION_FAILED++
        }

        # Delay between validations
        if ($script:DELAY_SECONDS -gt 0 -and -not $script:DRY_RUN) {
            Start-Sleep -Seconds $script:DELAY_SECONDS
        }
    }
}

# Run the validation phase
function Invoke-ValidationPhase {
    Write-Header "PHASE 3: MARKDOWN VALIDATION"

    if ($script:SKIP_VALIDATION) {
        Write-LogInfo "Skipping validation phase (--skip-validation)"
        return
    }

    if ($script:PARALLEL_JOBS -gt 1) {
        Invoke-ValidationLoopParallel
    } else {
        Invoke-ValidationLoopSequential
    }

    Write-Host ""
    Write-LogInfo "Validation Results:"
    Write-Host "    " -NoNewline
    Write-Host "Successful: " -ForegroundColor Green -NoNewline
    Write-Host $script:VALIDATION_SUCCESS
    Write-Host "    " -NoNewline
    Write-Host "Failed:     " -ForegroundColor Red -NoNewline
    Write-Host $script:VALIDATION_FAILED
}
