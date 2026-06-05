Add-Type -AssemblyName System.IO.Compression

$filePath = "Cyber Shield_SME 02.06.2026 1 (1).pdf"
$bytes = [System.IO.File]::ReadAllBytes($filePath)

$decodedTexts = New-Object System.Collections.Generic.List[string]
$streamCount = 0

$i = 0
while ($i -lt $bytes.Length - 10) {
    # Look for "stream" followed by CR+LF or LF
    if ($bytes[$i] -eq 0x73 -and $bytes[$i+1] -eq 0x74 -and $bytes[$i+2] -eq 0x72 -and 
        $bytes[$i+3] -eq 0x65 -and $bytes[$i+4] -eq 0x61 -and $bytes[$i+5] -eq 0x6D) {
        
        $dataStart = $i + 6
        if ($dataStart -lt $bytes.Length -and $bytes[$dataStart] -eq 0x0D) { $dataStart++ }
        if ($dataStart -lt $bytes.Length -and $bytes[$dataStart] -eq 0x0A) { $dataStart++ }
        
        # Find "endstream"
        $endTag = [System.Text.Encoding]::ASCII.GetBytes("endstream")
        $endPos = -1
        for ($j = $dataStart; $j -lt [Math]::Min($bytes.Length - 9, $dataStart + 2000000); $j++) {
            if ($bytes[$j] -eq $endTag[0]) {
                $match = $true
                for ($k = 1; $k -lt $endTag.Length; $k++) {
                    if ($j + $k -ge $bytes.Length -or $bytes[$j+$k] -ne $endTag[$k]) {
                        $match = $false
                        break
                    }
                }
                if ($match) { $endPos = $j; break }
            }
        }
        
        if ($endPos -gt $dataStart) {
            $streamLen = $endPos - $dataStart
            
            if ($streamLen -gt 20 -and $streamLen -lt 300000 -and $bytes[$dataStart] -eq 0x78) {
                # zlib compressed - try decompression
                $streamData = New-Object byte[] ($streamLen - 2)
                [System.Array]::Copy($bytes, $dataStart + 2, $streamData, 0, $streamLen - 2)
                
                try {
                    $ms = New-Object System.IO.MemoryStream(,$streamData)
                    $ds = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
                    $output = New-Object System.IO.MemoryStream
                    $buf = New-Object byte[] 4096
                    while (($read = $ds.Read($buf, 0, $buf.Length)) -gt 0) {
                        $output.Write($buf, 0, $read)
                    }
                    $decompressed = [System.Text.Encoding]::UTF8.GetString($output.ToArray())
                    if ($decompressed -match '[a-zA-Z\u00C0-\u024F\u1EA0-\u1EF9]{3,}') {
                        $decodedTexts.Add("=== STREAM $streamCount (compressed size: $streamLen) ===`n$($decompressed.Substring(0, [Math]::Min(1000, $decompressed.Length)))`n")
                    }
                } catch {
                    # ignore decompression errors
                }
            }
            
            $i = $endPos + 9
            $streamCount++
        } else {
            $i++
        }
    } else {
        $i++
    }
}

Write-Host "Total streams scanned: $streamCount"
Write-Host "Successfully decoded: $($decodedTexts.Count)"
Write-Host ""
foreach ($txt in $decodedTexts) {
    Write-Host $txt
    Write-Host "---"
}
