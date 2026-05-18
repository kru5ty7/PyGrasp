$folders = @(
    "f:\workspace\PyGrasp\content\01_Core",
    "f:\workspace\PyGrasp\content\02_Concurrency"
)

$renamed = 0

foreach ($folder in $folders) {
    $files = Get-ChildItem -Recurse -Filter "*.md" -Path $folder
    foreach ($file in $files) {
        # Only process NN-slug.md files
        if ($file.Name -notmatch "^\d+-(.+\.md)$") { continue }
        $newName = $Matches[1]   # e.g. "what-is-python.md"
        $newPath = Join-Path $file.DirectoryName $newName

        if (Test-Path $newPath) {
            Write-Host "  SKIP (exists): $newName"
            continue
        }

        Rename-Item -Path $file.FullName -NewName $newName
        Write-Host "  RENAMED: $($file.Name)  ->  $newName"
        $renamed++
    }
}

Write-Host "`nDone. Renamed $renamed file(s)."
