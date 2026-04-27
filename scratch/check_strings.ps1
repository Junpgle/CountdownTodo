$content = Get-Content 'd:\Codes\Android\math_quiz_app\lib\screens\course_screens.dart' -Raw
$inString = $false
$inStringChar = ''
$inComment = $false
$inBlockComment = $false

for ($i = 0; $i -lt $content.Length; $i++) {
    $c = $content[$i]
    $next = if ($i + 1 -lt $content.Length) { $content[$i+1] } else { '' }
    
    if ($inBlockComment) {
        if ($c -eq '*' -and $next -eq '/') {
            $inBlockComment = $false
            $i++
        }
    } elseif ($inComment) {
        if ($c -eq "`n") { $inComment = $false }
    } elseif ($inString) {
        if ($c -eq '\') { $i++ }
        elseif ($c -eq $inStringChar) { $inString = $false }
    } else {
        if ($c -eq '/' -and $next -eq '/') { $inComment = $true; $i++ }
        elseif ($c -eq '/' -and $next -eq '*') { $inBlockComment = $true; $i++ }
        elseif ($c -eq '"' -or $c -eq "'") { $inString = $true; $inStringChar = $c }
    }
}

if ($inString) { Write-Output "Unclosed string starting with $inStringChar" }
if ($inBlockComment) { Write-Output "Unclosed block comment" }
