$content = Get-Content 'd:\Codes\Android\math_quiz_app\lib\screens\course_screens.dart' -Raw
$count_ln = 1
$b1 = 0 # {}
$b2 = 0 # ()
$b3 = 0 # []
for ($i = 0; $i -lt $content.Length; $i++) {
    $c = $content[$i]
    if ($c -eq '{') { $b1++ } elseif ($c -eq '}') { $b1-- }
    elseif ($c -eq '(') { $b2++ } elseif ($c -eq ')') { $b2-- }
    elseif ($c -eq '[') { $b3++ } elseif ($c -eq ']') { $b3-- }
    
    if ($b1 -lt 0) { Write-Output "Line $count_ln : Extra }" ; break }
    if ($b2 -lt 0) { Write-Output "Line $count_ln : Extra )" ; break }
    if ($b3 -lt 0) { Write-Output "Line $count_ln : Extra ]" ; break }
    
    if ($c -eq "`n") { $count_ln++ }
}
Write-Output "Final balance: $b1 $b2 $b3"
