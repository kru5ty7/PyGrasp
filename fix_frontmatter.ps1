$files = Get-ChildItem -Recurse -Filter "*.md" -Path "f:\workspace\PyGrasp\content"
$fixed = 0

foreach ($file in $files) {
    $content = Get-Content $file.FullName -Raw -Encoding UTF8
    $lines   = $content -split "`n"
    $changed = $false
    $inFront = $false
    $count   = 0

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        if ($line.TrimEnd() -eq "---") {
            $count++
            if ($count -eq 1) { $inFront = $true }
            elseif ($count -eq 2) { $inFront = $false }
        }
        elseif ($inFront -and $line -match "^description:\s") {
            # Extract the value after "description: "
            if ($line -match "^(description:\s+)(.+)$") {
                $prefix = $Matches[1]
                $val    = $Matches[2]

                # Only fix if not already quoted
                $alreadyQuoted = $val.StartsWith('"') -or $val.StartsWith("'")
                $hasBracktick  = $val.Contains('`')
                $hasColonSpace = $val -match ":\s"

                if (-not $alreadyQuoted -and ($hasBracktick -or $hasColonSpace)) {
                    # Escape any double quotes inside the value
                    $escaped = $val -replace '"', '\"'
                    $lines[$i] = $prefix + '"' + $escaped + '"'
                    $changed = $true
                }
            }
        }
    }

    if ($changed) {
        $newContent = $lines -join "`n"
        [System.IO.File]::WriteAllText($file.FullName, $newContent, [System.Text.Encoding]::UTF8)
        Write-Host "FIXED: $($file.FullName)"
        $fixed++
    }
}

Write-Host ""
Write-Host "Done. Fixed $fixed file(s)."
