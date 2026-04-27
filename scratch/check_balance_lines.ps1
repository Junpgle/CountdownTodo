$content = Get-Content 'd:\Codes\Android\math_quiz_app\lib\screens\course_screens.dart' -Raw
$ln = 1
$balance = 0
for ($i = 0; $i -lt $content.Length; $i++) {
    $c = $content[$i]
    if ($c -eq '{') { $balance++ }
    elseif ($c -eq '}') { $balance-- }
    if ($c -eq "`n") {
        Write-Output "$ln : $balance"
        $ln++
    }
}
