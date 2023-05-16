function Get-FirewallRuleState {
    param (
        [string]$RuleName
    )

    # Get the firewall rule with the specified name
    $rule = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue

    if ($rule) {
        #Write-Output $rule.Enabled
        if ($rule.Enabled -eq $True) {
            return "Open"
        } else {
            return "Closed"
        }
    } else {
        return "Not Configured"
    }
}

function Set-PsFirewallPort {
    param (
        [bool]$Enabled
    )

    $ruleName = "Powershell HTTP server port"
    $port = 8080

    $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

    if ($existingRule -eq $null) {
        # Firewall rule doesn't exist yet, so create it
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -LocalPort $port -Protocol TCP -Action Allow
        $existingRule = Get-NetFirewallRule -DisplayName $ruleName
    }

    if ($Enabled){
        Set-NetFirewallRule -InputObject $existingRule -Enabled True
    }else{
        Set-NetFirewallRule -InputObject $existingRule -Enabled False
    }    
}

function Convert-FileSize {
    param(
        [parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [long]$Size
    )

    $units = @("B", "KB", "MB", "GB", "TB")
    $index = 0

    while ($Size -ge 1024 -and $index -lt 4) {
        $Size /= 1024
        $index++
    }

    return "$Size $($units[$index])"
}

function Get-UniqueFileName($filename) {
    $folder = Split-Path $filename -Parent
    $basename = [System.IO.Path]::GetFileNameWithoutExtension($filename)
    $extension = [System.IO.Path]::GetExtension($filename)

    $counter = 1
    while (Test-Path $filename) {
        # The file already exists, so add a counter to the filename
        
        $filename = "{0}\{1}({2}){3}" -f $folder, $basename, $counter, $extension
        $counter++
    }
    return $filename
}


function HTTPstreamToFile([System.IO.BinaryReader]$reader,[String]$saveFolder){
    $outputStream = 0 # Stream
    $outputWriter = 0 # Stream

    # MULTIPART FORM DATA
    $parseState = 0 # 0 = searchForStart, 1 = Search for end of header, 2 = Search for end of filecontent, 3 = done.
    $BoundaryString = New-Object byte[] 200
    $lastTwoBytes = New-Object byte[] 2
    $lastTwoBytes_Length = 0
    $matchFound_prev = $false

    # Read from the stream into a buffer
    $buffer = New-Object byte[] 2048
    $delimiterBytes = [byte[]]@(13, 10)
    $delimiterMatchLength = 0
    $buffer_usedLength = 0
    $done = $false

    while (!$done){
        $buffer_usedLength += $reader.Read($buffer, $buffer_usedLength, $buffer.Length - $buffer_usedLength)
        $done = (0 -eq $buffer_usedLength) # Check if we are done only when we dont find more matches.    
    
        $matchFound_prev = $matchFound
        $matchFound = $false
        $removelength = $buffer_usedLength # matchindex -> removelength
        $i = 0
        while((!$matchFound) -and ($i -lt  $buffer_usedLength)){  # find first occurence of the delimiter
            if ($buffer[$i] -eq $delimiterBytes[$delimiterMatchLength]){
                $delimiterMatchLength +=1
            }
            else{
                $delimiterMatchLength = 0
            }
            if ($delimiterMatchLength -eq 2){
                 #Write-Output "match"  
                 $removelength = $i+1;
                 $delimiterMatchLength = 0
                 $matchFound = $true
            }        
            $i++
        }    
        if (!$done){
            # HANDLE THE BUFFER HERE
                    
            if ($parseState -eq 0){
                $parseState = 1
                $BoundaryString = $buffer[0..($removelength-3)]
                #Write-Output $BoundaryString
                #[System.Console]::WriteLine([System.Text.Encoding]::ASCII.GetString($BoundaryString, 0, $BoundaryString.Length))
            }
            elseif($parseState -eq 1){
            
                $line = [System.Text.Encoding]::ASCII.GetString($buffer[0..($buffer_usedLength-1)])
                       
                $regex = '(?<=filename=").*?(?=")'
                if ($line -match $regex) {  # If filename is found make a filestream to store the file.
                    $filename = $matches[0]
                
                    $outputFile = Join-Path $saveFolder $fileName
                    $outputFile = Get-UniqueFileName -filename $outputFile
                    Write-Output $outputFile
                    $outputStream = New-Object System.IO.FileStream($outputFile, [System.IO.FileMode]::Create)
                    $outputWriter = New-Object System.IO.BinaryWriter($outputStream)                
                } 

                if($buffer[0]-eq 13 -and $buffer[1] -eq 10 -and $removelength -eq 2 -and $matchFound_prev) # Found empty line
                { 
                    $parseState = 2
                }
            }
            elseif($parseState -eq 2){
            
                $result = Compare-Object -ReferenceObject $BoundaryString -DifferenceObject $buffer[0..($BoundaryString.Length-1)] -SyncWindow 0
                if ($result.Count -eq 0) {
                    $parseState = 3
                
                } else {                
                    $outputWriter.Write($lastTwoBytes, 0, $lastTwoBytes_Length) # Write the two last bytes from previous iteration

                    $lastTwoBytes[0]=$buffer[$removelength-2] # Save the two last bytes from the current iteration
                    $lastTwoBytes[1]=$buffer[$removelength-1]
                    $lastTwoBytes_Length = [Math]::Min(2,$buffer_usedLength)

                    $outputWriter.Write($buffer, 0, $removelength-2) # Write bytes to file except the two last
                }
            
            }
            elseif($parseState -eq 3){
                # Dont do anything
            }               
        }      
        $buffer_usedLength -= $removelength 
        #[System.Buffer]::BlockCopy($buffer, $removelength, $buffer, 0, $buffer_usedLength)        
        [System.Array]::Copy($buffer, $removelength, $buffer, 0, $buffer_usedLength)                  
    }
$outputWriter.Close()
$outputStream.Close()

}

function GetHtmlPage ($computerPath, $webAddress, $serverUrls) {
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="UTF-8">
	<meta name="viewport" content="width=device-width, initial-scale=1.0">
	<title>File Browser</title>
	<link rel="shortcut icon" href="data:image/x-icon;base64,AAABAAEAEBAQAAEABAAoAQAAFgAAACgAAAAQAAAAIAAAAAEABAAAAAAAgAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAA/4QAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEQAAAAAAAAARAAAAAAAAABEAAAAAAAAAEQAAAAAAAAARAAAAAAAAABEAAAAAAAAAEQAAAAAAAAAREREQARERERERERABERERAAAAAAAAABEAAAAAAAAAEQAAAAAAAAARAAAAAAAAABEAAAAAAAAAEQAAAAAAAAARAAAAAAAAABE//wAAP/8AAD5/AAA+fwAAPn8AAD5/AAA+fwAAAAAAAAAAAAD+fAAA/nwAAP58AADgBAAA4AQAAP/8AAD//AAA" />
	<!-- <link rel="stylesheet" href="style.css"> -->
	<style>
/* Global Styles */
body {
	font-family: Arial, sans-serif;
	margin: 0;
	padding: 0;
}
.header {
  background-color: #272838; //#424b54; //#35a7ff; //#fafafa;
  border-bottom: 1px solid #dcdcdc;
  margin-bottom: 30px;
  padding: 20px;
  text-align: center;
}
.header h1 {
  font-size: 32px;
  margin-bottom: 10px;
  color: #FFFFFF
}
.container {
	max-width: 1200px;
	margin: 0 auto;
	padding: 20px;
	display: flex;
	flex-wrap: wrap;
	justify-content: space-between;
}
.card {
	width: calc(50% - 20px);
	background-color: #fff;
	border-radius: 10px;
	box-shadow: 0 5px 10px rgba(0, 0, 0, 0.1);
	margin-bottom: 20px;
	overflow: hidden;
}
.card-header {
	background-color: #f5f5f5;
	padding: 10px 20px;
	border-bottom: 1px solid #ccc;
}
.card-body {
	padding: 20px;
}
.card-body ul {
	list-style: none;
	margin: 0;
	padding: 0;
}
.card-body ul li {
	padding: 10px 0;
	border-bottom: 1px solid #f5f5f5;
	display: flex;
	align-items: center;
	justify-content: space-between;
}
.card-body ul li a {
	color: #333;
	text-decoration: none;
}
.filesize {
	color: #999;
	font-size: 14px;
}
/* Media Queries */
@media screen and (max-width: 768px) {
	.container {
		flex-direction: column;
	}
	.card {
		width: 100%;
	}
}
li:hover {
			background-color: #F2F2F2;
		}
		
		.btnlink:link, .btnlink:visited {
  background-color: white;
  color: black;
  border: 2px solid #272838;
  padding: 10px 20px;
  text-align: center;
  text-decoration: none;
  display: inline-block;
  border-radius: 10px;
}
.btnlink:hover, .btnlink:active {
  background-color: #272838;
  color: white;
}
input[type=submit], input[type=file]::file-selector-button {
  margin-right: 20px;
  border: 2px solid #272838;
  background: white;
  padding: 10px 20px;
  border-radius: 10px;
  color: #000;
  cursor: pointer;
  transition: background .2s ease-in-out;
}
input[type=submit]:hover, input[type=file]::file-selector-button:hover {
  background: #272838;
  color: white;
}
	</style>
</head>
<body>
	<header class="header">
    <h1>TIPS - Powershell File Server</h1>
  </header>
	<div class="container">		
		<div class="card">
			<div class="card-header">
				<h2>Folders</h2>
			</div>
			<div class="card-body">
				<ul class="folder-list">
"@


$parentfolder = Split-Path $curPath_Web -Parent
$html += "<li><a href='$parentfolder'>..</a></li>"



#Write-Host $computerPath
Get-ChildItem -Path $computerPath -Directory -Depth 0 | ForEach-Object {
    $linkpath = Join-Path -Path $curPath_Web -ChildPath $_.Name
    $html += "<li><a href='$linkpath'>$($_.Name)</a></li>"
    #Write-Host $_.Name
}

$html += @"
					
				</ul>
			</div>
		</div>
		<div class="card">
			<div class="card-header">
				<h2>Files</h2>
			</div>
			<div class="card-body">
				<ul class="file-list">
"@

Get-ChildItem -Path $computerPath -File -Depth 0 | ForEach-Object {
    $linkpath = Join-Path -Path $curPath_Web -ChildPath $_.Name
    $html += "<li><a href='$linkpath'>$($_.Name)</a><span class='filesize'>($(Convert-FileSize -Size $_.Length))</span></li>"
    #Write-Host $_.Name
}

$html += @"
				</ul>
			</div>
		</div>
		
		<div class="card">
			<div class="card-header">
				<h2>Server Info</h2>
			</div>
			<div class="card-body">			
			
			<p>Server adresses:</p>
"@

foreach ($url in $serverUrls)
{
    $html += "<a href='$url' target='_blank'>$url</a><br>"
}
  
$html += @"		
<br>
 <form method="GET" action="?">  
    <input type="submit" value="Stop server" ></input>  
    <input type="hidden" id="cmd" name="cmd" value="stop" />
</form>
<hr>
"@

$ruleState = Get-FirewallRuleState -RuleName "Powershell HTTP server port"
$html += "<p>Firewall port: $ruleState</p>"

$html += @"
 <form method="GET" action="?" style="display: inline-block;">  
    <input type="submit" value="Open firewall port" data-inline="true"></input>  
    <input type="hidden" id="setfirewall" name="setfirewall" value="open" />
</form >
 <form method="GET" action="?" style="display: inline-block;">  
    <input type="submit" value="Close firewall port" data-inline="true"></input>  
    <input type="hidden" id="setfirewall" name="setfirewall" value="close" />
</form>
"@





$html += @"
			</div>
		</div>
		<div class="card">
			<div class="card-header">
				<h2>Upload File</h2>
			</div>
			<div class="card-body">
"@
			$html+= "<p>Current folder: '$webAddress'</p>"						


$html += "<form method='post' action='$curPath_Web' enctype='multipart/form-data'>"

$html += @"
				
					<input type="file" name="file">
					<input type="submit" value="Upload">
				</form>	
			</div>
		</div>			
	</div>
</body>
</html>
"@
    return $html
}




# Check if the script is running as an administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    # Open a new PowerShell process with elevation
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $psi.Verb = "runas"

    [System.Diagnostics.Process]::Start($psi) | Out-Null
} else {
    

    #--------- Adding IP adresses and starting HTTP listener ----------#
    $port = 8080
    #$prefix = "http://10.0.0.82:$port/"
    $listener = New-Object System.Net.HttpListener
    # Get a list of all the IPv4 addresses assigned to network adapters on the computer
    $ipAddresses = Get-NetIPAddress | Where-Object {$_.AddressFamily -eq "IPv4"}
    $prefixList = @()
    foreach ($ipAddress in $ipAddresses) {      # Loop through the IPv4 addresses and check if their associated adapter is up
        $adapter = Get-NetAdapter | Where-Object {$_.InterfaceIndex -eq $ipAddress.InterfaceIndex}
        if ($adapter.Status -eq "Up") {
            $ipString = $ipAddress.IPAddress.ToString()
            $prefix = "http://$($ipString):$port/"
            Write-Host $prefix
            $prefixList += $prefix
            $listener.Prefixes.Add($prefix)
        }
    }
    $listener.Start()


    # ----- Open web browser ----- #
    $enumerator = $listener.Prefixes.GetEnumerator()
    if ($enumerator.MoveNext()) {
        $firstPrefix = $enumerator.Current
        Write-Host "Opening browser at: $firstPrefix"
        Start-Process $firstPrefix
    } else {
        Write-Host "No prefixes found."
    }


    $basePathPC = $MyInvocation.MyCommand.Path | Split-Path -Parent
    Write-Host $basePathPC
    #$basePathPC = "C:\Users\BjørnVegardTveraaen\Downloads"
    $curPath_PC = ""
    $curPath_Web = ""

    Write-Host "Starting main loop."
    # ----- Main loop ----- #
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
         Write-Output "request received:"

        $curPath_Web = $request.Url.LocalPath
        $curPath_PC  = Join-Path -Path $basePathPC -ChildPath $curPath_Web
        #Write-Output $curPath_PC
        Write-Output $curPath_Web

        if ($request.HttpMethod -eq "GET") {
        
            if (Test-Path $curPath_PC -PathType Container) 
            {

                # ----- Check if the Get request contains any parameters ----- #
                        
                $queryString = $request.Url.Query
                $queryString = $queryString.TrimStart("?")
                $parts = $queryString.Split("&")

                foreach ($part in $parts) {
                    $nameValue = $part.Split("=")
                    $name = [System.Uri]::UnescapeDataString($nameValue[0])
                    $value = if ($nameValue.Length -gt 1) {
                        [System.Uri]::UnescapeDataString($nameValue[1])
                    } else {
                        $null
                    }
                
                    if($name -eq "setfirewall" -and $value -eq "open"){
                        Write-Host "Opening firewall port"
                        Set-PsFirewallPort -Enabled $true
                    }
                    
                    if($name -eq "setfirewall" -and $value -eq "close"){
                        Write-Host "Closing firewall port"
                        Set-PsFirewallPort -Enabled $false
                    }

                    if($name -eq "cmd" -and $value -eq "stop"){
                        Write-Output "Stopping the server"
                        # stop the server
                        $listener.Stop()
                    }

                }

                if (!$listener.IsListening){
                    break # If listener was set to stop, break immediately to avoid unnecessary errors.
                }
            






                # ----- Display web page for current folder ----- #
                # 
                Write-Output "Serving the web page
                "
                $response.ContentType = "text/html"
                $response.StatusCode = 200
                $response.StatusDescription = "OK"

                $html = GetHtmlPage $curPath_PC $curPath_Web $prefixList
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.Close()

            }
            elseif (Test-Path $curPath_PC -PathType Leaf)
            {
                # serve file to the user.
                Write-Output "Serving the file to the user"

                $filename = Split-Path -Leaf $curPath_PC
			
                $response.ContentType = "application/octet-stream"
                $response.Headers.Add("Content-Disposition", "attachment; filename=$filename")
                $response.ContentLength64 = (Get-Item  $curPath_PC).Length
                $response.SendChunked = $false
                $stream = $response.OutputStream
                $fileStream = New-Object System.IO.FileStream( $curPath_PC, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
                $buffer = New-Object byte[] 4096
                while ($true) {
                    $read = $fileStream.Read($buffer, 0, $buffer.Length)
                    if ($read -eq 0) {
                        break
                    }
                    $stream.Write($buffer, 0, $read)
                }
                $fileStream.Close()
                $stream.Close()
            }
            else
            {
                # Not found error message
                $response.StatusCode = 404
                $response.StatusDescription = "Not Found"
                $response.Close()
            }
        
        
        }
        elseif ($request.HttpMethod -eq "POST") {
            # Store the uploaded file on the computer
            Write-Output "Receiving file"
            Write-Output $curPath_Web
            $stream = $request.InputStream
            HTTPstreamToFile -reader $stream -saveFolder $curPath_PC
            #
            $response.StatusCode = 302
            $response.RedirectLocation = "/"
            $response.Close()
        }
    }
    $listener.Stop()


}
