$folders = @(
    "f:\workspace\PyGrasp\content\01_Core",
    "f:\workspace\PyGrasp\content\02_Concurrency"
)

$updated = 0

foreach ($folder in $folders) {
    $files = Get-ChildItem -Recurse -Filter "*.md" -Path $folder
    foreach ($file in $files) {
        # Only process NN-slug files
        if ($file.Name -notmatch "^(\d+)-(.+)\.md$") { continue }
        $originalSlug = $Matches[2]   # e.g. "descriptors", "classmethod-staticmethod"

        $content = Get-Content $file.FullName -Raw -Encoding UTF8
        $lines   = $content -split "`n"

        # Skip if aliases already present in frontmatter
        $hasAlias = $false
        $inFront  = $false
        $count    = 0
        $insertAt = -1

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($line.TrimEnd() -eq "---") {
                $count++
                if ($count -eq 1) { $inFront = $true }
                elseif ($count -eq 2) { $insertAt = $i; break }
            }
            if ($inFront -and $line -match "^aliases:") {
                $hasAlias = $true; break
            }
        }

        if ($hasAlias -or $insertAt -lt 0) { continue }

        # Insert aliases line just before the closing ---
        $aliasList = "aliases: [$originalSlug]"
        $newLines  = $lines[0..($insertAt - 1)] + $aliasList + $lines[$insertAt..($lines.Count - 1)]

        [System.IO.File]::WriteAllText($file.FullName, ($newLines -join "`n"), [System.Text.Encoding]::UTF8)
        Write-Host "ALIASED: $($file.Name)  ->  aliases: [$originalSlug]"
        $updated++
    }
}

Write-Host "`nDone. Added aliases to $updated file(s)."
