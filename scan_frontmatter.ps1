$files = Get-ChildItem -Recurse -Filter "*.md" -Path "f:\workspace\PyGrasp\content"
$issues = @()

foreach ($file in $files) {
    $lines = Get-Content $file.FullName
    $inFront = $false
    $count = 0

    foreach ($line in $lines) {
        if ($line -eq "---") {
            $count++
            if ($count -eq 1) { $inFront = $true }
            elseif ($count -eq 2) { $inFront = $false; break }
        }
        elseif ($inFront -and $line -match "^description:\s") {
            $val = $line -replace "^description:\s+", ""
            $startsWithQuote = $val.StartsWith('"') -or $val.StartsWith("'")
            $hasBracktick   = $val.Contains('`')
            $hasColonSpace  = $val -match ":\s"
            if (-not $startsWithQuote -and ($hasBracktick -or $hasColonSpace)) {
                $issues += [PSCustomObject]@{
                    File    = $file.FullName
                    Line    = $line.Substring(0, [Math]::Min($line.Length, 120))
                }
            }
        }
    }
}

if ($issues.Count -eq 0) {
    Write-Host "No issues found."
} else {
    Write-Host "Found $($issues.Count) problematic description field(s):"
    foreach ($i in $issues) {
        Write-Host ""
        Write-Host "FILE: $($i.File)"
        Write-Host "LINE: $($i.Line)"
    }
}
