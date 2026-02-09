<#
.SYNOPSIS
    Reads backlog from project path and returns issue counts

.DESCRIPTION
    Scans docs/backlog/*/issues/ directories to count total and completed issues

.PARAMETER ProjectPath
    Path to the project root directory
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath
)

try {
    $result = @{
        totalIssues     = 0
        completedIssues = 0
        currentIssue    = ""
        backlogPath     = ""
        error           = $null
    }
    
    # Find backlog directory - try direct path first
    $backlogBase = Join-Path $ProjectPath "docs\backlog"
    
    if (-not (Test-Path $backlogBase)) {
        # Search recursively for docs/backlog folder (max 2 levels deep)
        $docsFolder = Get-ChildItem -Path $ProjectPath -Directory -Recurse -Depth 2 | 
        Where-Object { $_.Name -eq "docs" } | 
        Select-Object -First 1
        
        if ($docsFolder) {
            $backlogBase = Join-Path $docsFolder.FullName "backlog"
        }
    }
    
    if (-not (Test-Path $backlogBase)) {
        $result.error = "No backlog found at $backlogBase or in subdirectories"
        $result | ConvertTo-Json -Compress
        exit
    }
    
    # Find first version folder (v1.0, v2.0, etc.)
    $versionDirs = Get-ChildItem -Path $backlogBase -Directory | Where-Object { $_.Name -match "^v\d" } | Sort-Object Name -Descending
    if ($versionDirs.Count -eq 0) {
        $result.error = "No version directories found in backlog"
        $result | ConvertTo-Json -Compress
        exit
    }
    
    $latestVersion = $versionDirs[0]
    $issuesPath = Join-Path $latestVersion.FullName "issues"
    $result.backlogPath = $issuesPath
    
    if (-not (Test-Path $issuesPath)) {
        $result.error = "No issues directory found at $issuesPath"
        $result | ConvertTo-Json -Compress
        exit
    }
    
    # Count issues
    $issueFiles = Get-ChildItem -Path $issuesPath -Filter "*.md"
    $result.totalIssues = $issueFiles.Count
    
    $completed = 0
    $firstIncomplete = $null
    
    foreach ($file in $issueFiles | Sort-Object Name) {
        $content = Get-Content $file.FullName -Raw
        
        # Check for completion status - match "Status:" followed by various done indicators
        # Patterns: Done, Completado, Complete, ✅, Hecho, Terminado, DONE (case insensitive)
        $isDone = $content -match "Status:.*Done" -or 
        $content -match "Status:.*Completado" -or 
        $content -match "Status:.*Complete" -or
        $content -match "Status:.*✅" -or
        $content -match "Status:.*Hecho" -or
        $content -match "Status:.*Terminado" -or
        $content -match "(?i)Status:.*DONE"
        
        if ($isDone) {
            $completed++
        }
        elseif ($null -eq $firstIncomplete) {
            # First incomplete issue - extract ID from filename
            if ($file.Name -match "^([A-Z]+-\d+)") {
                $firstIncomplete = $matches[1]
            }
        }
    }
    
    $result.completedIssues = $completed
    $result.currentIssue = if ($firstIncomplete) { $firstIncomplete } else { "DONE" }
    
    $result | ConvertTo-Json -Compress
}
catch {
    @{
        totalIssues     = 0
        completedIssues = 0
        currentIssue    = ""
        backlogPath     = ""
        error           = $_.Exception.Message
    } | ConvertTo-Json -Compress
}
