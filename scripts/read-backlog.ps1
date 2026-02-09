<#
.SYNOPSIS
    Reads backlog from project path and returns issue counts

.DESCRIPTION
    Supports multiple backlog formats:
    - 'auto': Tries docs/backlog/vX/issues/ first, then BacklogPath as folder, then as file, then fuzzy search
    - 'file': Single .md file with checkboxes (- [ ] / - [x]) or Status: Done markers
    - 'folder': All .md files in folder, each file = 1 issue, uses Status: Done to check completion

.PARAMETER ProjectPath
    Path to the project root directory

.PARAMETER BacklogPath
    Optional custom path to the backlog (relative to ProjectPath or absolute)

.PARAMETER Mode
    Discovery mode: 'auto', 'file', or 'folder' (default: 'auto')
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [Parameter(Mandatory = $false)]
    [string]$BacklogPath = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("auto", "file", "folder")]
    [string]$Mode = "auto"
)

# Helper: Check if a status line indicates completion
function Test-IsCompleted {
    param([string]$Content)
    return ($Content -match "Status:.*Done" -or 
        $Content -match "Status:.*Completado" -or 
        $Content -match "Status:.*Complete" -or
        $Content -match "Status:.*✅" -or
        $Content -match "Status:.*Hecho" -or
        $Content -match "Status:.*Terminado" -or
        $Content -match "(?i)Status:.*DONE")
}

# Helper: Parse a single file with checkboxes (- [ ] / - [x])
function Read-FileBacklog {
    param([string]$FilePath)
    
    $result = @{
        totalIssues     = 0
        completedIssues = 0
        currentIssue    = ""
        backlogPath     = $FilePath
        error           = $null
    }

    if (-not (Test-Path $FilePath)) {
        $result.error = "File not found: $FilePath"
        return $result
    }

    $content = Get-Content $FilePath -Raw
    
    # Count checkbox-style items: - [ ] and - [x]
    $unchecked = [regex]::Matches($content, '- \[ \]')
    $checked = [regex]::Matches($content, '- \[x\]')
    
    # Also count * [ ] and * [x] style
    $unchecked2 = [regex]::Matches($content, '\* \[ \]')
    $checked2 = [regex]::Matches($content, '\* \[x\]')
    
    $totalUnchecked = $unchecked.Count + $unchecked2.Count
    $totalChecked = $checked.Count + $checked2.Count
    $total = $totalUnchecked + $totalChecked
    
    if ($total -gt 0) {
        $result.totalIssues = $total
        $result.completedIssues = $totalChecked
        
        # Find first unchecked item text
        $lines = $content -split "`n"
        foreach ($line in $lines) {
            if ($line -match '[-*]\s\[ \]\s*(.+)') {
                $result.currentIssue = $matches[1].Trim()
                break
            }
        }
        if (-not $result.currentIssue -and $totalUnchecked -eq 0) {
            $result.currentIssue = "DONE"
        }
    }
    else {
        # Fallback: count markdown headers (## or ###) as issues and check Status: in each section
        $sections = [regex]::Split($content, '(?m)^#{2,3}\s')
        if ($sections.Count -gt 1) {
            $result.totalIssues = $sections.Count - 1  # First split is before first header
            $completed = 0
            $firstIncomplete = $null
            for ($i = 1; $i -lt $sections.Count; $i++) {
                if (Test-IsCompleted $sections[$i]) {
                    $completed++
                }
                elseif ($null -eq $firstIncomplete) {
                    $headerLine = ($sections[$i] -split "`n")[0].Trim()
                    $firstIncomplete = $headerLine
                }
            }
            $result.completedIssues = $completed
            $result.currentIssue = if ($firstIncomplete) { $firstIncomplete } else { "DONE" }
        }
        else {
            $result.error = "No checkboxes or sections found in file"
        }
    }
    
    return $result
}

# Helper: Parse a folder of .md files (each file = 1 issue)
function Read-FolderBacklog {
    param([string]$FolderPath)
    
    $result = @{
        totalIssues     = 0
        completedIssues = 0
        currentIssue    = ""
        backlogPath     = $FolderPath
        error           = $null
    }

    if (-not (Test-Path $FolderPath)) {
        $result.error = "Folder not found: $FolderPath"
        return $result
    }

    $issueFiles = Get-ChildItem -Path $FolderPath -Filter "*.md"
    $result.totalIssues = $issueFiles.Count
    
    if ($issueFiles.Count -eq 0) {
        $result.error = "No .md files found in folder: $FolderPath"
        return $result
    }

    $completed = 0
    $firstIncomplete = $null
    
    foreach ($file in $issueFiles | Sort-Object Name) {
        $content = Get-Content $file.FullName -Raw
        
        if (Test-IsCompleted $content) {
            $completed++
        }
        elseif ($null -eq $firstIncomplete) {
            # Extract ID from filename (APP-001, ISSUE-1, etc.) or use filename
            if ($file.Name -match '^([A-Za-z]+-\d+)') {
                $firstIncomplete = $matches[1]
            }
            else {
                $firstIncomplete = $file.BaseName
            }
        }
    }
    
    $result.completedIssues = $completed
    $result.currentIssue = if ($firstIncomplete) { $firstIncomplete } else { "DONE" }
    
    return $result
}

# Helper: Try the original docs/backlog/vX/issues/ structure
function Read-ClassicBacklog {
    param([string]$ProjectPath)
    
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
        return $null
    }
    
    # Find first version folder (v1.0, v2.0, etc.)
    $versionDirs = Get-ChildItem -Path $backlogBase -Directory | Where-Object { $_.Name -match "^v\d" } | Sort-Object Name -Descending
    if ($versionDirs.Count -eq 0) {
        return $null
    }
    
    $latestVersion = $versionDirs[0]
    $issuesPath = Join-Path $latestVersion.FullName "issues"
    
    if (-not (Test-Path $issuesPath)) {
        return $null
    }
    
    return Read-FolderBacklog -FolderPath $issuesPath
}

# Helper: Fuzzy search for backlog-like files
function Find-BacklogFuzzy {
    param([string]$ProjectPath)
    
    # Search for files/folders matching *backlog* (max 3 levels)
    $backlogItems = Get-ChildItem -Path $ProjectPath -Recurse -Depth 3 | 
    Where-Object { $_.Name -match "backlog" -and $_.Name -notmatch "node_modules|\.git|target|dist" }
    
    foreach ($item in $backlogItems) {
        if ($item.PSIsContainer) {
            # It's a folder — try reading as folder backlog
            $result = Read-FolderBacklog -FolderPath $item.FullName
            if (-not $result.error) { return $result }
        }
        elseif ($item.Extension -eq ".md") {
            # It's a file — try reading as file backlog
            $result = Read-FileBacklog -FilePath $item.FullName
            if (-not $result.error) { return $result }
        }
    }
    
    return $null
}

# ─── Main Logic ───

try {
    $finalResult = $null

    # Resolve custom BacklogPath to absolute if provided
    $resolvedPath = ""
    if ($BacklogPath -and $BacklogPath -ne "") {
        if ([System.IO.Path]::IsPathRooted($BacklogPath)) {
            $resolvedPath = $BacklogPath
        }
        else {
            $resolvedPath = Join-Path $ProjectPath $BacklogPath
        }
    }

    switch ($Mode) {
        "file" {
            if ($resolvedPath) {
                $finalResult = Read-FileBacklog -FilePath $resolvedPath
            }
            else {
                $finalResult = @{
                    totalIssues = 0; completedIssues = 0; currentIssue = ""; backlogPath = ""
                    error       = "Mode 'file' requires a BacklogPath"
                }
            }
        }
        "folder" {
            if ($resolvedPath) {
                $finalResult = Read-FolderBacklog -FolderPath $resolvedPath
            }
            else {
                $finalResult = @{
                    totalIssues = 0; completedIssues = 0; currentIssue = ""; backlogPath = ""
                    error       = "Mode 'folder' requires a BacklogPath"
                }
            }
        }
        "auto" {
            # 1) Try custom path first (if specified)
            if ($resolvedPath) {
                if (Test-Path $resolvedPath -PathType Leaf) {
                    $finalResult = Read-FileBacklog -FilePath $resolvedPath
                }
                elseif (Test-Path $resolvedPath -PathType Container) {
                    $finalResult = Read-FolderBacklog -FolderPath $resolvedPath
                }
            }
            
            # 2) Try classic docs/backlog/vX/issues/
            if (-not $finalResult -or $finalResult.error) {
                $classicResult = Read-ClassicBacklog -ProjectPath $ProjectPath
                if ($classicResult -and -not $classicResult.error) {
                    $finalResult = $classicResult
                }
            }
            
            # 3) Fuzzy search for *backlog* files/folders
            if (-not $finalResult -or $finalResult.error) {
                $fuzzyResult = Find-BacklogFuzzy -ProjectPath $ProjectPath
                if ($fuzzyResult -and -not $fuzzyResult.error) {
                    $finalResult = $fuzzyResult
                }
            }
            
            # 4) Final fallback
            if (-not $finalResult) {
                $finalResult = @{
                    totalIssues = 0; completedIssues = 0; currentIssue = ""; backlogPath = ""
                    error       = "No backlog found in project (tried custom path, docs/backlog, and fuzzy search)"
                }
            }
        }
    }

    $finalResult | ConvertTo-Json -Compress
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
