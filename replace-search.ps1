Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Use Git to select only tracked HTML files that still contain the retired action.
# This keeps reruns fast even though the mirror contains thousands of HTML files.
$files = @(
    git grep -l -I 'somnus-xv.github.io/TAC-DB-Test-/search' -- '*.html' '*.htm' 2>$null
)

# Match only the decommissioned local search form so the script is safe to rerun.
$oldSearchRegex = '(?is)<form\b(?=[^>]*\bid=["'']search["''])(?=[^>]*\baction=["'']https://somnus-xv\.github\.io/TAC-DB-Test-/search["''])[^>]*>.*?</form\s*>'

# The new Google-powered search form HTML
$newSearchHtml = @"
<form id="search" class="my-2 my-lg-0 flex-grow-1" action="https://www.google.com/search" method="get" target="_blank">
  <input type="hidden" name="as_sitesearch" value="somnus-xv.github.io/TAC-DB-Test-">
  <div class="input-group input-group-sm">
      <input type="text" name="q" id="s" class="form-control" placeholder="Search database via Google…" autocomplete="off" aria-label="Search the database…">
    <span class="input-group-btn">
      <button type="submit" class="btn btn-sm btn-primary">
        <i class="fa-solid fa-magnifying-glass"></i>
      </button>            </span>
  </div>
</form>
"@

$changed = 0
$pendingWrites = @{}
$errors = @()

foreach ($path in $files) {
    try {
        $full = Join-Path (Get-Location) $path
        $bytes = [IO.File]::ReadAllBytes($full)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
        $start = if ($hasBom) { 3 } else { 0 }
        $text = [Text.Encoding]::UTF8.GetString($bytes, $start, $bytes.Length - $start)

        # Check if the file contains the old search form
        if ([regex]::IsMatch($text, $oldSearchRegex)) {
            $updated = [regex]::Replace($text, $oldSearchRegex, $newSearchHtml)

            if ($updated -cne $text) {
                $newBytes = [Text.Encoding]::UTF8.GetBytes($updated)
                if ($hasBom) { $newBytes = [byte[]](239, 187, 191) + $newBytes }
                $pendingWrites[$full] = $newBytes
            }
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

try {
    foreach ($path in $pendingWrites.Keys) {
        [IO.File]::WriteAllBytes($path, $pendingWrites[$path])
        $changed++
    }
} catch {
    throw "Write failed after $changed files: $($_.Exception.Message)"
}

Write-Host "HTML files scanned: $($files.Count)"
Write-Host "Search bars updated: $changed"

git diff --check
if ($LASTEXITCODE -ne 0) { throw 'git diff --check reported whitespace errors.' }
Write-Host 'git diff --check: passed'

# Verification check for any remaining old search forms
$remaining = @(git grep -n -I 'somnus-xv.github.io/TAC-DB-Test-/search' -- '*.html' '*.htm' 2>$null)
if ($remaining.Count -gt 0) {
    throw "Some old search forms still remain!"
}

$googleForms = @(git grep -l -I 'www.google.com/search' -- '*.html' '*.htm' 2>$null)
$missingSiteRestriction = @(
    $googleForms |
    Where-Object {
        $content = [IO.File]::ReadAllText((Join-Path (Get-Location) $_))
        $content -notmatch '(?is)<form\b(?=[^>]*\baction=["'']https://www\.google\.com/search["''])[^>]*>.*?</form\s*>' -or
        $content -notmatch '(?is)<form\b(?=[^>]*\baction=["'']https://www\.google\.com/search["''])[^>]*>.*?name=["'']as_sitesearch["''][^>]*value=["'']somnus-xv\.github\.io/TAC-DB-Test-["''].*?</form\s*>'
    }
)
if ($googleForms.Count -eq 0 -or $missingSiteRestriction.Count -gt 0) {
    throw 'Google search verification failed: missing Google forms or site restrictions.'
}

Write-Host "Final Verification: Passed. All search bars successfully updated to Google Site Search."