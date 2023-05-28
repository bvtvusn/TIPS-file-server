function Generate-FilePageHtml {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType 'Leaf'})]
        [string]$FilePath,
		[Parameter(Mandatory = $true)]
        [string]$FileUrl
    )
	
	$picEextensions = @(".JPG", ".JPEG", ".JFIF", ".PJPEG", ".PJP", ".PNG", ".GIF", ".TIFF", ".BMP", ".PSD", ".SVG", ".APNG", ".AVIF", ".WEBP", ".ICO", ".CUR", ".TIF", ".TIFF")

    # Get the file extension
    $fileExtension = [System.IO.Path]::GetExtension($FilePath).ToUpper()
	
	$FileType = "text"
	if ($picEextensions -contains $fileExtension) {
		$FileType = "picture"
	}
	elseif (".PDF" -like $fileExtension){
		$FileType = "pdf"
	}
	
	
    # Define the HTML code based on the file type
    switch ($FileType) {
        'text' {
            # Text-based file: Display content in <pre> tag
            $fileContent = Get-Content -Path $FilePath -Raw
			$escapedContent = [System.Web.HttpUtility]::HtmlEncode($fileContent)
            $htmlCode = @"
<!DOCTYPE html>
<html>
<head>
<title>File Viewer</title>
</head>
<body>
<pre>$escapedContent</pre>
</body>
</html>
"@
        }
        'picture' {
            # Image file: Display in <img> tag
            $htmlCode = @"
<!DOCTYPE html>
<html>
<head>
<title>File Viewer</title>
</head>
<body>
<img src="$FileUrl" alt="Image">
</body>
</html>
"@
        }
        'pdf' {
            # PDF file: Display in <embed> tag
            $htmlCode = @"
<!DOCTYPE html>
<html>
<head>
<title>File Viewer</title>
</head>
<body>



<a href="$FileUrl" target="_blank" rel="noopener noreferrer">Open PDF</a>

</body>
</html>
"@
        }
        default {
            Write-Error "Unsupported file type: $fileExtension"
            return
        }
    }

    return $htmlCode
}


function Get-Size {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (Test-Path -Path $Path) {
        $itemType = (Get-Item -Path $Path).PSIsContainer
        if ($itemType) {
            $size = (Get-ChildItem -Path $Path -Recurse | Measure-Object -Property Length -Sum).Sum
        } else {
            $size = (Get-Item -Path $Path).Length
        }

        return $size
    } else {
        return -1  # Path does not exist
    }
}

function Test-PathType {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (Test-Path -Path $Path) {
        $itemType = (Get-Item -Path $Path).PSIsContainer
        if ($itemType) {
            return 2  # Folder
        } else {
            return 1  # File
        }
    } else {
        return 0  # Does not exist
    }
}

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

function GetCSS(){
	$myCss = @"
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



table { 
    border-collapse: collapse; 	
}
tr + tr > td{
  border-top: 1px solid black;
  border-color: lightgrey;
}
td {
    padding: 0 15px;
  }
"@
	
	return $myCss
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
"@

$html += GetCSS
$html += @"
	</style>
</head>
<body>

	<svg style="display: none" version="2.0">  
	  <defs>  
		<symbol id="download-badge">  
		   <path d="M.5 9.9a.5.5 0 0 1 .5.5v2.5a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-2.5a.5.5 0 0 1 1 0v2.5a2 2 0 0 1-2 2H2a2 2 0 0 1-2-2v-2.5a.5.5 0 0 1 .5-.5z"/>
			<path d="M7.646 11.854a.5.5 0 0 0 .708 0l3-3a.5.5 0 0 0-.708-.708L8.5 10.293V1.5a.5.5 0 0 0-1 0v8.793L5.354 8.146a.5.5 0 1 0-.708.708l3 3z"/>
		</symbol>  
	  </defs>  

	  <use href="#download-badge" />  
	</svg> 
	
	
	
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
    $html += "<li><a href='$($linkpath)?page=info'>$($_.Name)</a><div><span class='filesize'>($(Convert-FileSize -Size $_.Length))</span><a href='$linkpath'><svg width='32' height='16' viewBox='0 0 16 16' version='2.0'><use href='#download-badge' /></svg></a></div></li>"
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
    $html += "<a href='$($url.Prefix)' target='_blank'>$($url.Prefix)  ($($url.AdapterName))</a><br>"
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


function GetHtmlInfoPage ($computerPath, $webAddress, $InfoObject) {
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
"@

$html += GetCSS
$html += @"
	</style>
</head>
<body>
	<header class="header">
    <h1>TIPS - Powershell File Server</h1>
  </header>
  <a class="container" href="javascript:history.back() style="color: black;">
	  <svg xmlns="http://www.w3.org/2000/svg" width="50" height="50" fill="currentColor" class="bi bi-box-arrow-left" viewBox="0 0 16 16">
		  <path fill-rule="evenodd" d="M6 12.5a.5.5 0 0 0 .5.5h8a.5.5 0 0 0 .5-.5v-9a.5.5 0 0 0-.5-.5h-8a.5.5 0 0 0-.5.5v2a.5.5 0 0 1-1 0v-2A1.5 1.5 0 0 1 6.5 2h8A1.5 1.5 0 0 1 16 3.5v9a1.5 1.5 0 0 1-1.5 1.5h-8A1.5 1.5 0 0 1 5 12.5v-2a.5.5 0 0 1 1 0v2z"/>
		  <path fill-rule="evenodd" d="M.146 8.354a.5.5 0 0 1 0-.708l3-3a.5.5 0 1 1 .708.708L1.707 7.5H10.5a.5.5 0 0 1 0 1H1.707l2.147 2.146a.5.5 0 0 1-.708.708l-3-3z"/>
	  </svg>
  </a>
	<div class="container">	


	
		<div class="card">
			<div class="card-header">
				<h2>$($InfoObject.ObjType) Info</h2>
			</div>
			<div class="card-body">
				
				<table>
				  <tbody>
					<tr><td>
"@
					$html += "File Name:"  
					$html += "</td><td>" 
					$html += "<a href='$($webAddress)'>$($InfoObject.FileName)</a>"
					$html += "</td></tr><tr><td>"
					
					$html += "Path:"  
					$html += "</td><td>" 
					$html += "$($InfoObject.Path)"
					$html += "</td></tr><tr><td>"
					
					$html += "Creation Date:"  
					$html += "</td><td>" 
					$html += "$($InfoObject.CreationDate)"
					$html += "</td></tr><tr><td>"
					
					$html += "Last Write Time:"  
					$html += "</td><td>" 
					$html += "$($InfoObject.LastWriteTime)"
					$html += "</td></tr><tr><td>"
					
					
					
					$html += "Size:"  
					$html += "</td><td>" 
					$html += "$($InfoObject.Size)"
					$html += "</td></tr><tr><td>"
					
					
					
					$html += "View:"  
					$html += "</td><td>" 
					$html += "<a href='$($linkpath)?page=view'>File content</a>"
					$html += "</td></tr>"
					
					
					
					
					
					
$html += @"
</tbody>
				</table>
				
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
	foreach ($ipAddress in $ipAddresses) {
		$adapter = Get-NetAdapter | Where-Object { $_.InterfaceIndex -eq $ipAddress.InterfaceIndex }		
		if ($adapter.Status -eq "Up") {
			$ipString = $ipAddress.IPAddress.ToString()
			$prefix = "http://$($ipString):$port/"			
			$prefixObject = [PSCustomObject]@{
				Prefix = $prefix
				AdapterName = $adapter.Name
			}			
			Write-Host $prefixObject.Prefix			
			$prefixList += $prefixObject
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
		$ElementTypeRequested = Test-PathType -Path $curPath_PC #0 = does not exist, 1 = file, 2 = folder
        #Write-Output $curPath_PC
        Write-Output $curPath_Web

        if ($request.HttpMethod -eq "GET") {
			
			$detailPageFlag = $false
			$viewPageFlag = $false
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
				if($name -eq "page" -and $value -eq "info"){
					$detailPageFlag = $true
				}
				if($name -eq "page" -and $value -eq "view"){
					$viewPageFlag = $true
				}

			}

			if (!$listener.IsListening){
				break # If listener was set to stop, break immediately to avoid unnecessary errors.
			}
				
			if($viewPageFlag -eq $true -AND $ElementTypeRequested -ne 0){ # element not equal to invalid
				# ----- xxx ----- #
                # 
                Write-Output "Serving the file viewer page"
				
                $response.ContentType = "text/html"
                $response.StatusCode = 200
                $response.StatusDescription = "OK"

				$html = Generate-FilePageHtml -FilePath $curPath_PC -FileUrl $curPath_Web
				
				
				

                
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.Close()
				
			}
			elseif($detailPageFlag -eq $true -AND $ElementTypeRequested -ne 0){ # element not equal to invalid
				# ----- xxx ----- #
                # 
                Write-Output "Serving the details page"
				
                $response.ContentType = "text/html"
                $response.StatusCode = 200
                $response.StatusDescription = "OK"


				$ItemInfoObject = [PSCustomObject]@{
					ObjType = "a"
					Path = "b"
					FileName = "f"
					CreationDate = "c"
					LastWriteTime = "L"
					Size = "d"
				}				
				if (Test-Path $curPath_PC -PathType Leaf){
					$ItemInfoObject.ObjType = "File"
				}
				else 
				{
					$ItemInfoObject.ObjType = "Folder"
				}
				$ItemInfoObject.Path = $curPath_Web
				$filesize = Get-Size -Path $curPath_PC
				$ItemInfoObject.Size = Convert-FileSize -Size $filesize
				
				$file = Get-Item -Path $curPath_PC
				$ItemInfoObject.CreationDate = $file.CreationTime.ToString("dd.MM.yyyy HH:mm:ss")
				$ItemInfoObject.LastWriteTime = $file.LastWriteTime.ToString("dd.MM.yyyy HH:mm:ss")
				$ItemInfoObject.FileName = $file.Name
				#Write-Output $ItemInfoObject.ObjType
				
				

                $html = GetHtmlInfoPage $curPath_PC $curPath_Web $ItemInfoObject
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.Close()
				
			}	
            elseif ($ElementTypeRequested -eq 2) # Found folder
            {

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
            elseif ($ElementTypeRequested -eq 1) # Found file
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
                # "Not found" error message
				Write-Output "404, page not found"
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
Read-Host