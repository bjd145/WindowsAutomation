Start-Process -FilePath "c:\Windows\System32\Sysprep\sysprep.exe" -ArgumentList @("/oobe", "/generalize", "/shutdown", "/quiet") 