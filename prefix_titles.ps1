$folders = @(
    "f:\workspace\PyGrasp\content\01_Core",
    "f:\workspace\PyGrasp\content\02_Concurrency"
)

$updated = 0

foreach ($folder in $folders) {
    $files = Get-ChildItem -Recurse -Filter "*.md" -Path $folder
    foreach ($file in $files) {
        # Only process files that start with NN- (e.g. 01-what-is-python.md)
        if ($file.Name -notmatch "^(\d+)-(.+)\.md$") { continue }
        $num = $Matches[1]  # e.g. "01"

        $content = Get-Content $file.FullName -Raw -Encoding UTF8
        $lines   = $content -split "`n"

        $inFront = $false
        $count   = 0
        $changed = $false

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($line.TrimEnd() -eq "---") {
                $count++
                if ($count -eq 1) { $inFront = $true }
                elseif ($count -eq 2) { break }
                continue
            }
            if ($inFront -and $line -match "^(title:\s+)(.+)$") {
                $prefix  = $Matches[1]
                $current = $Matches[2].Trim('"')

                # Skip if already prefixed (starts with digits and a dash/space)
                if ($current -match "^\d+\s*-\s*") { break }

                $newTitle  = "$num - $current"
                # Re-wrap in quotes if needed (title may contain colons/backticks)
                if ($newTitle -match "[:`"`']" ) {
                    $newTitle = '"' + $newTitle + '"'
                }
                $lines[$i] = $prefix + $newTitle
                $changed = $true
                break
            }
        }

        if ($changed) {
            [System.IO.File]::WriteAllText($file.FullName, ($lines -join "`n"), [System.Text.Encoding]::UTF8)
            Write-Host "UPDATED: $($file.FullName -replace '.*content\\', 'content\')"
            $updated++
        }
    }
}

Write-Host "`nDone. Updated $updated file(s)."
