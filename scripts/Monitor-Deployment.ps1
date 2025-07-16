#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Monitor GitHub Actions deployment progress in real-time.

.DESCRIPTION
    This script monitors GitHub Actions workflows and provides real-time updates
    on deployment progress. It can be used to track the deployment status
    after pushing to main or testing branches.

.PARAMETER Owner
    The GitHub repository owner (default: current git remote)

.PARAMETER Repo
    The GitHub repository name (default: current git remote)

.PARAMETER Branch
    The branch to monitor (default: current branch)

.PARAMETER WorkflowFile
    The workflow file to monitor (default: auto-detect based on branch)

.PARAMETER PollInterval
    Polling interval in seconds (default: 10)

.PARAMETER MaxWaitTime
    Maximum wait time in minutes (default: 30)

.EXAMPLE
    .\Monitor-Deployment.ps1
    
.EXAMPLE
    .\Monitor-Deployment.ps1 -Branch "main" -MaxWaitTime 45
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$Owner = "",
    
    [Parameter(Mandatory = $false)]
    [string]$Repo = "",
    
    [Parameter(Mandatory = $false)]
    [string]$Branch = "",
    
    [Parameter(Mandatory = $false)]
    [string]$WorkflowFile = "",
    
    [Parameter(Mandatory = $false)]
    [int]$PollInterval = 10,
    
    [Parameter(Mandatory = $false)]
    [int]$MaxWaitTime = 30
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Function to get repository info from git
function Get-GitRepoInfo {
    try {
        $remoteUrl = git config --get remote.origin.url
        if ($remoteUrl -match "github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?/?$") {
            return @{
                owner = $matches[1]
                repo = $matches[2]
            }
        }
    } catch {
        return $null
    }
    return $null
}

# Function to get current branch
function Get-CurrentBranch {
    try {
        return git rev-parse --abbrev-ref HEAD
    } catch {
        return "main"
    }
}

# Function to check if gh CLI is available
function Test-GitHubCLI {
    try {
        gh --version | Out-Null
        return $true
    } catch {
        return $false
    }
}

# Function to get workflow status
function Get-WorkflowStatus {
    param(
        [string]$Owner,
        [string]$Repo,
        [string]$WorkflowFile
    )
    
    try {
        $runs = gh run list --repo "$Owner/$Repo" --workflow "$WorkflowFile" --limit 1 --json "status,conclusion,createdAt,url,databaseId" | ConvertFrom-Json
        if ($runs.Count -gt 0) {
            return $runs[0]
        }
    } catch {
        return $null
    }
    return $null
}

# Function to get workflow run details
function Get-WorkflowRunDetails {
    param(
        [string]$Owner,
        [string]$Repo,
        [string]$RunId
    )
    
    try {
        $details = gh run view $RunId --repo "$Owner/$Repo" --json "jobs,status,conclusion,createdAt,updatedAt,url"
        return $details | ConvertFrom-Json
    } catch {
        return $null
    }
}

# Function to format duration
function Format-Duration {
    param([datetime]$StartTime)
    
    $duration = (Get-Date) - $StartTime
    if ($duration.TotalMinutes -lt 1) {
        return "$([math]::Round($duration.TotalSeconds))s"
    } elseif ($duration.TotalHours -lt 1) {
        return "$([math]::Round($duration.TotalMinutes))m $([math]::Round($duration.Seconds))s"
    } else {
        return "$([math]::Round($duration.TotalHours))h $([math]::Round($duration.Minutes))m"
    }
}

# Function to get status emoji
function Get-StatusEmoji {
    param([string]$Status, [string]$Conclusion)
    
    switch ($Status) {
        "queued" { return "⏳" }
        "in_progress" { return "🔄" }
        "completed" {
            switch ($Conclusion) {
                "success" { return "✅" }
                "failure" { return "❌" }
                "cancelled" { return "🚫" }
                "skipped" { return "⏭️" }
                default { return "❓" }
            }
        }
        default { return "❓" }
    }
}

# Main monitoring process
Write-ColorOutput "🔍 GitHub Actions Deployment Monitor" "Yellow"
Write-ColorOutput "=================================" "Yellow"

# Check if gh CLI is available
if (-not (Test-GitHubCLI)) {
    Write-ColorOutput "❌ GitHub CLI (gh) is not available!" "Red"
    Write-ColorOutput "   Please install GitHub CLI: https://cli.github.com/" "Red"
    exit 1
}

# Get repository info
if (-not $Owner -or -not $Repo) {
    $repoInfo = Get-GitRepoInfo
    if (-not $repoInfo) {
        Write-ColorOutput "❌ Unable to determine repository info from git remote" "Red"
        Write-ColorOutput "   Please specify -Owner and -Repo parameters" "Red"
        exit 1
    }
    $Owner = $repoInfo.owner
    $Repo = $repoInfo.repo
}

# Get current branch
if (-not $Branch) {
    $Branch = Get-CurrentBranch
}

# Determine workflow file
if (-not $WorkflowFile) {
    switch ($Branch) {
        "main" { $WorkflowFile = "deploy-main.yml" }
        "testing" { $WorkflowFile = "deploy-testing.yml" }
        default { $WorkflowFile = "deploy-$Branch.yml" }
    }
}

Write-ColorOutput "📊 Monitoring Configuration:" "Cyan"
Write-ColorOutput "   🏢 Repository: $Owner/$Repo" "Gray"
Write-ColorOutput "   🌿 Branch: $Branch" "Gray"
Write-ColorOutput "   📄 Workflow: $WorkflowFile" "Gray"
Write-ColorOutput "   ⏱️  Poll Interval: $PollInterval seconds" "Gray"
Write-ColorOutput "   ⌛ Max Wait Time: $MaxWaitTime minutes" "Gray"

$startTime = Get-Date
$lastStatus = ""
$lastRunId = ""
$jobStatuses = @{}

Write-ColorOutput "`n🔄 Starting monitoring..." "Yellow"

while ($true) {
    $elapsed = (Get-Date) - $startTime
    
    # Check if we've exceeded max wait time
    if ($elapsed.TotalMinutes -gt $MaxWaitTime) {
        Write-ColorOutput "`n⏰ Maximum wait time exceeded ($MaxWaitTime minutes)" "Yellow"
        break
    }
    
    # Get latest workflow run
    $workflowRun = Get-WorkflowStatus -Owner $Owner -Repo $Repo -WorkflowFile $WorkflowFile
    
    if ($workflowRun) {
        $runId = $workflowRun.databaseId
        $status = $workflowRun.status
        $conclusion = $workflowRun.conclusion
        $emoji = Get-StatusEmoji -Status $status -Conclusion $conclusion
        
        # Check if this is a new run or status change
        if ($runId -ne $lastRunId -or $status -ne $lastStatus) {
            $duration = Format-Duration -StartTime $startTime
            Write-ColorOutput "`n[$duration] $emoji Workflow Status: $status" "White"
            
            if ($conclusion) {
                Write-ColorOutput "   📋 Conclusion: $conclusion" "Gray"
            }
            
            Write-ColorOutput "   🔗 URL: $($workflowRun.url)" "Gray"
            
            # Get detailed job information
            $runDetails = Get-WorkflowRunDetails -Owner $Owner -Repo $Repo -RunId $runId
            
            if ($runDetails -and $runDetails.jobs) {
                Write-ColorOutput "   📝 Jobs:" "Gray"
                
                foreach ($job in $runDetails.jobs) {
                    $jobEmoji = Get-StatusEmoji -Status $job.status -Conclusion $job.conclusion
                    $jobStatus = if ($job.conclusion) { $job.conclusion } else { $job.status }
                    
                    # Only show status change or first time
                    if ($jobStatuses[$job.name] -ne $jobStatus) {
                        Write-ColorOutput "      $jobEmoji $($job.name): $jobStatus" "Gray"
                        $jobStatuses[$job.name] = $jobStatus
                    }
                }
            }
            
            $lastStatus = $status
            $lastRunId = $runId
        }
        
        # Check if workflow is complete
        if ($status -eq "completed") {
            $duration = Format-Duration -StartTime $startTime
            Write-ColorOutput "`n🏁 Workflow completed after $duration" "Yellow"
            
            if ($conclusion -eq "success") {
                Write-ColorOutput "🎉 Deployment completed successfully!" "Green"
                Write-ColorOutput "   🔗 View details: $($workflowRun.url)" "Green"
                
                # Suggest running verification
                Write-ColorOutput "`n💡 Next steps:" "Cyan"
                Write-ColorOutput "   Run deployment verification:" "Gray"
                Write-ColorOutput "   .\scripts\Verify-Deployment.ps1 -ClientName 'elite' -Environment '$Branch'" "Gray"
                Write-ColorOutput "   .\scripts\Verify-Deployment.ps1 -ClientName 'jarandes' -Environment '$Branch'" "Gray"
                
            } else {
                Write-ColorOutput "❌ Deployment failed!" "Red"
                Write-ColorOutput "   🔗 View details: $($workflowRun.url)" "Red"
                
                # Show job failures
                if ($runDetails -and $runDetails.jobs) {
                    $failedJobs = $runDetails.jobs | Where-Object { $_.conclusion -eq "failure" }
                    if ($failedJobs) {
                        Write-ColorOutput "   💥 Failed jobs:" "Red"
                        foreach ($job in $failedJobs) {
                            Write-ColorOutput "      • $($job.name)" "Red"
                        }
                    }
                }
            }
            break
        }
    } else {
        $duration = Format-Duration -StartTime $startTime
        Write-ColorOutput "[$duration] ⏳ No recent workflow runs found for $WorkflowFile" "Yellow"
    }
    
    # Wait before next poll
    Start-Sleep -Seconds $PollInterval
}

Write-ColorOutput "`n✅ Monitoring completed!" "Green"
