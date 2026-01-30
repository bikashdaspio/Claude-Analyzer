# ═══════════════════════════════════════════════════════════════════════════════
# DOCX Conversion Phase
# ═══════════════════════════════════════════════════════════════════════════════

# Prevent multiple sourcing
if ($script:_CONVERSION_LOADED) { return }
$script:_CONVERSION_LOADED = $true

# Convert a single markdown file to DOCX
# Usage: Convert-ToDocx "md_file" "docx_output"
function Convert-ToDocx {
    param(
        [Parameter(Mandatory=$true)][string]$MdFile,
        [Parameter(Mandatory=$true)][string]$DocxOutput
    )

    Write-LogDebug "Converting: $MdFile -> $DocxOutput"

    if ($script:DRY_RUN) {
        Write-LogInfo "[DRY-RUN] Would convert: $MdFile -> $DocxOutput"
        return $true
    }

    # Ensure output directory exists
    $outputDir = Split-Path -Parent $DocxOutput
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    # Find reference doc - try multiple locations
    $refDocPath = Join-Path $script:SCRIPT_DIR "custom-reference.docx"
    if (-not (Test-Path $refDocPath)) {
        # Try parent directory (repository root)
        $refDocPath = Join-Path (Split-Path -Parent $script:SCRIPT_DIR) "custom-reference.docx"
    }

    $logFile = Join-Path $script:LOG_DIR "conversion_$([System.IO.Path]::GetFileNameWithoutExtension($MdFile)).log"

    try {
        $pandocArgs = @(
            $MdFile,
            "-f", "markdown",
            "-t", "docx",
            "--wrap=auto"
        )

        # Add reference doc if it exists
        if (Test-Path $refDocPath) {
            $pandocArgs += "--reference-doc=$refDocPath"
        }

        $pandocArgs += @("-o", $DocxOutput)

        $errorOutput = & pandoc @pandocArgs 2>&1
        $exitCode = $LASTEXITCODE

        if ($errorOutput) {
            $errorOutput | Out-File -FilePath $logFile -Encoding UTF8
        }

        if ($exitCode -eq 0) {
            return $true
        } else {
            Write-LogError "Conversion failed for $MdFile (exit code: $exitCode)"
            return $false
        }
    } catch {
        Write-LogError "Conversion failed for $MdFile : $_"
        "ERROR: $_" | Out-File -FilePath $logFile -Encoding UTF8
        return $false
    }
}

# Launch conversion as a background job
function Start-ConversionJob {
    param(
        [string]$MdFile,
        [string]$DocxOutput
    )

    $resultFile = Join-Path $script:PARALLEL_RESULTS_DIR "result_conv_$(Get-Random)_$(Get-Date -Format 'HHmmssffff')"

    $job = Start-Job -ScriptBlock {
        param($MdFile, $DocxOutput, $ResultFile, $LogDir, $ScriptDir, $DryRun)

        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($MdFile)

        Write-Host "[START] Converting: $fileName"

        if ($DryRun) {
            Write-Host "[DRY-RUN] Would convert: $fileName"
            "success $MdFile" | Out-File -FilePath $ResultFile -Encoding UTF8
            return
        }

        # Ensure output directory exists
        $outputDir = Split-Path -Parent $DocxOutput
        if (-not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        # Find reference doc
        $refDocPath = Join-Path $ScriptDir "custom-reference.docx"
        if (-not (Test-Path $refDocPath)) {
            $refDocPath = Join-Path (Split-Path -Parent $ScriptDir) "custom-reference.docx"
        }

        $logFile = Join-Path $LogDir "conversion_${fileName}.log"

        try {
            $pandocArgs = @(
                $MdFile,
                "-f", "markdown",
                "-t", "docx",
                "--wrap=auto"
            )

            if (Test-Path $refDocPath) {
                $pandocArgs += "--reference-doc=$refDocPath"
            }

            $pandocArgs += @("-o", $DocxOutput)

            $errorOutput = & pandoc @pandocArgs 2>&1
            $exitCode = $LASTEXITCODE

            if ($errorOutput) {
                $errorOutput | Out-File -FilePath $logFile -Encoding UTF8
            }

            if ($exitCode -eq 0) {
                "success $MdFile" | Out-File -FilePath $ResultFile -Encoding UTF8
                Write-Host "[DONE] Converted: $fileName -> $([System.IO.Path]::GetFileName($DocxOutput))"
            } else {
                "failed $MdFile" | Out-File -FilePath $ResultFile -Encoding UTF8
                Write-Host "[FAIL] Conversion failed: $fileName"
            }
        } catch {
            "failed $MdFile" | Out-File -FilePath $ResultFile -Encoding UTF8
            Write-Host "[FAIL] Conversion failed: $fileName ($_)"
        }
    } -ArgumentList $MdFile, $DocxOutput, $resultFile, $script:LOG_DIR, $script:SCRIPT_DIR, $script:DRY_RUN

    [void]$script:PARALLEL_JOBS_LIST.Add($job)
    Write-LogDebug "Launched conversion job $($job.Id) for $([System.IO.Path]::GetFileName($MdFile))"
}

# Derive DOCX output path from markdown file
function Get-DocxOutputPath {
    param([string]$MdFile)

    # Get relative path from Documents dir
    $relPath = $MdFile.Substring($script:DOCS_DIR.Length).TrimStart('\', '/')
    $dirPart = Split-Path -Parent $relPath
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($MdFile)

    # Create output path: Documents/DOCX/{subdir}/{filename}.docx
    if ([string]::IsNullOrEmpty($dirPart) -or $dirPart -eq ".") {
        return Join-Path $script:DOCX_OUTPUT_DIR "${baseName}.docx"
    } else {
        return Join-Path $script:DOCX_OUTPUT_DIR $dirPart "${baseName}.docx"
    }
}

# Collect conversion results
function Get-ConversionResults {
    $resultFiles = Get-ChildItem -Path $script:PARALLEL_RESULTS_DIR -Filter "result_conv_*" -ErrorAction SilentlyContinue

    foreach ($rf in $resultFiles) {
        $content = Get-Content $rf.FullName -ErrorAction SilentlyContinue
        if ($content) {
            $parts = $content -split ' ', 2
            $status = $parts[0]

            switch ($status) {
                "success" { $script:CONVERSION_SUCCESS++ }
                "failed"  { $script:CONVERSION_FAILED++ }
            }
            Remove-Item $rf.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

# Main conversion loop (parallel)
function Invoke-ConversionLoopParallel {
    $mdFiles = Find-MarkdownFiles

    if ($mdFiles.Count -eq 0) {
        Write-LogWarn "No markdown files found to convert"
        return
    }

    Write-LogInfo "Found $($mdFiles.Count) markdown files to convert"
    Write-LogInfo "Running conversion in parallel with $script:PARALLEL_JOBS concurrent jobs"

    # Create output directory
    if (-not (Test-Path $script:DOCX_OUTPUT_DIR)) {
        New-Item -ItemType Directory -Path $script:DOCX_OUTPUT_DIR -Force | Out-Null
    }

    # Initialize parallel processing
    Initialize-Parallel

    $jobsLaunched = 0

    foreach ($mdFile in $mdFiles) {
        $docxOutput = Get-DocxOutputPath -MdFile $mdFile

        # Wait for a slot if at capacity
        Wait-ForSlot

        # Launch the job
        Start-ConversionJob -MdFile $mdFile -DocxOutput $docxOutput
        $jobsLaunched++
    }

    # Wait for all remaining jobs
    if ($script:PARALLEL_JOBS_LIST.Count -gt 0) {
        Wait-ForAllJobs
    }

    # Collect any remaining results
    Get-ConversionResults

    Write-LogInfo "Conversion complete. Launched $jobsLaunched jobs."

    # Cleanup
    Remove-ParallelResources
}

# Main conversion loop (sequential)
function Invoke-ConversionLoopSequential {
    $mdFiles = Find-MarkdownFiles

    if ($mdFiles.Count -eq 0) {
        Write-LogWarn "No markdown files found to convert"
        return
    }

    Write-LogInfo "Found $($mdFiles.Count) markdown files to convert"

    # Create output directory
    if (-not (Test-Path $script:DOCX_OUTPUT_DIR)) {
        New-Item -ItemType Directory -Path $script:DOCX_OUTPUT_DIR -Force | Out-Null
    }

    foreach ($mdFile in $mdFiles) {
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($mdFile)
        $docxOutput = Get-DocxOutputPath -MdFile $mdFile

        Write-LogInfo "Converting: $fileName"

        if (Convert-ToDocx -MdFile $mdFile -DocxOutput $docxOutput) {
            Write-LogSuccess "Converted: $fileName -> $([System.IO.Path]::GetFileName($docxOutput))"
            $script:CONVERSION_SUCCESS++
        } else {
            Write-LogError "Failed: $fileName"
            $script:CONVERSION_FAILED++
        }
    }
}

# Run the conversion phase
function Invoke-ConversionPhase {
    Write-Header "PHASE 4: DOCX CONVERSION"

    if ($script:SKIP_CONVERSION) {
        Write-LogInfo "Skipping conversion phase (--skip-conversion)"
        return
    }

    # Check pandoc is available
    if (-not (Test-Pandoc)) {
        Write-LogError "Cannot proceed with conversion without pandoc"
        return
    }

    if ($script:PARALLEL_JOBS -gt 1) {
        Invoke-ConversionLoopParallel
    } else {
        Invoke-ConversionLoopSequential
    }

    Write-Host ""
    Write-LogInfo "Conversion Results:"
    Write-Host "    " -NoNewline
    Write-Host "Successful: " -ForegroundColor Green -NoNewline
    Write-Host $script:CONVERSION_SUCCESS
    Write-Host "    " -NoNewline
    Write-Host "Failed:     " -ForegroundColor Red -NoNewline
    Write-Host $script:CONVERSION_FAILED
    Write-Host ""
    Write-LogInfo "DOCX files saved to: $script:DOCX_OUTPUT_DIR"
}
