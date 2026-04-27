$content = Get-Content 'd:\Codes\Android\math_quiz_app\lib\screens\course_screens.dart' -Raw
$count = 0
for ($i = 0; $i -lt $content.Length; $i++) {
    if ($content[$i] -eq '(') { $count++ }
    elseif ($content[$i] -eq ')') { 
        $count-- 
        if ($count -lt 0) {
            $line = ($content.Substring(0, $i) -split "`n").Count
            Write-Output "Negative balance for () reached at line $line"
            $count = 0
        }
    }
}
if ($count -ne 0) {
    Write-Output "Final () balance is $count"
}

$count = 0
for ($i = 0; $i -lt $content.Length; $i++) {
    if ($content[$i] -eq '[') { $count++ }
    elseif ($content[$i] -eq ']') { 
        $count-- 
        if ($count -lt 0) {
            $line = ($content.Substring(0, $i) -split "`n").Count
            Write-Output "Negative balance for [] reached at line $line"
            $count = 0
        }
    }
}
if ($count -ne 0) {
    Write-Output "Final [] balance is $count"
}
