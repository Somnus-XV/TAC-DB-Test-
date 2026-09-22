Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$oldGitPattern = 'https://www\.alchemistcodedb\.com|https://cdn\.alchemistcodedb\.com|(\.\./)+cdn\.alchemistcodedb\.com|(\.\./)+cdn\.jsdelivr\.net|(\.\./)+unpkg\.com'
$files = @(git grep -Il -E $oldGitPattern -- '*.html' '*.htm' '*.js' '*.css' '*.json' '*.txt')

$literalTargets = @(
    [Tuple]::Create('https://cdn.alchemistcodedb.com', 'https://somnus-xv.github.io/TAC-DB-Test-/cdn.alchemistcodedb.com'),
    [Tuple]::Create('https://www.alchemistcodedb.com', 'https://somnus-xv.github.io/TAC-DB-Test-')
)

$regexTargets = @(
    [Tuple]::Create('(?:\.\./)+cdn\.alchemistcodedb\.com', 'https://somnus-xv.github.io/TAC-DB-Test-/cdn.alchemistcodedb.com'),
    [Tuple]::Create('(?:\.\./)+cdn\.jsdelivr\.net', 'https://somnus-xv.github.io/TAC-DB-Test-/cdn.jsdelivr.net'),
    [Tuple]::Create('(?:\.\./)+unpkg\.com', 'https://somnus-xv.github.io/TAC-DB-Test-/unpkg.com')
)

$oldPatterns = @(
    'https://www\.alchemistcodedb\.com',
    'https://cdn\.alchemistcodedb\.com',
    '(?:\.\./)+cdn\.alchemistcodedb\.com',
    '(?:\.\./)+cdn\.jsdelivr\.net',
    '(?:\.\./)+unpkg\.com'
)

$counts = @{}
foreach ($target in $literalTargets) { $counts[$target.Item1] = 0 }
foreach ($target in $regexTargets) { $counts[$target.Item1] = 0 }

$pendingWrites = @{}
$errors = @()

foreach ($path in $files) {
    try {
        $full = Join-Path (Get-Location) $path
        $bytes = [IO.File]::ReadAllBytes($full)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
        $start = if ($hasBom) { 3 } else { 0 }
        $text = [Text.Encoding]::UTF8.GetString($bytes, $start, $bytes.Length - $start)
        $updated = $text

        foreach ($target in $literalTargets) {
            $count = ([regex]::Matches($updated, [regex]::Escape($target.Item1))).Count
            if ($count -gt 0) {
                $counts[$target.Item1] += $count
                $updated = $updated.Replace($target.Item1, $target.Item2)
            }
        }

        foreach ($target in $regexTargets) {
            $count = ([regex]::Matches($updated, $target.Item1)).Count
            if ($count -gt 0) {
                $counts[$target.Item1] += $count
                $updated = [regex]::Replace($updated, $target.Item1, $target.Item2)
            }
        }

        foreach ($pattern in $oldPatterns) {
            if ([regex]::IsMatch($updated, $pattern)) {
                throw "Old URL pattern remains after replacement: $pattern"
            }
        }

        if ($updated -cne $text) {
            $newBytes = [Text.Encoding]::UTF8.GetBytes($updated)
            if ($hasBom) { $newBytes = [byte[]](239, 187, 191) + $newBytes }
            $pendingWrites[$full] = $newBytes
        }
    } catch {
        $errors += "${path}: $($_.Exception.Message)"
    }
}

if ($errors.Count -gt 0) {
    Write-Host "Errors: $($errors.Count) - No files were modified."
    $errors | Select-Object -First 20 | ForEach-Object { Write-Host $_ }
    exit 1
}

$changed = 0
try {
    foreach ($path in $pendingWrites.Keys) {
        [IO.File]::WriteAllBytes($path, $pendingWrites[$path])
        $changed++
    }
} catch {
    throw "Write failed after $changed files: $($_.Exception.Message)"
}

Write-Host "Candidate files scanned: $($files.Count)"
Write-Host "Changed files: $changed"
foreach ($entry in $counts.GetEnumerator() | Sort-Object Name) {
    Write-Host "$($entry.Name): $($entry.Value)"
}

git diff --check
if ($LASTEXITCODE -ne 0) { throw 'git diff --check reported whitespace errors.' }

foreach ($pattern in $oldPatterns) {
    $remaining = @(git grep -n -E $pattern -- '*.html' '*.htm' '*.js' '*.css' '*.json' '*.txt' 2>$null)
    if ($LASTEXITCODE -notin @(0, 1)) { throw "git grep failed for pattern: $pattern" }
    if ($remaining.Count -gt 0) { throw "Old URL pattern remains: $pattern" }
}

Write-Host 'git diff --check: passed'
Write-Host 'Final Verification: Passed. No old URL patterns detected.'
