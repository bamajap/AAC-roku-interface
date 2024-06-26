﻿function Get-RokuDeviceName {
    param (
        [string]$IPAddress
    )

    
    # Construct the URL for the device info endpoint
    $url = "http://$($IPAddress):8060/query/device-info"

    try {
        # Send an HTTP GET request to the Roku device
        $response = Invoke-WebRequest -Uri $url -Method Get

        # Parse the XML response
        [xml]$deviceInfo = $response.Content

        # Extract the friendly device name
        $friendlyName = $deviceInfo.'device-info'.'friendly-device-name'
        $deviceLocation = $deviceInfo.'device-info'.'user-device-location'

        return "$($friendlyName) ($($deviceLocation))"
    }
    catch {
        Write-Error "Failed to query device info from Roku at $IPAddress. $_"
        return $null
    }
}

function Find-Roku
{
    <#
    .Synopsis
        Finds Rokus
    .Description
        Finds Rokus on your local area network, using SSDP.
    .Link
        Get-Roku
    .Example
        Find-Roku | Get-Roku
    #>
    [OutputType('Roku.BasicInfo')]
    [CmdletBinding()]
    param(
        # The search timeout, in seconds. Increase this number on
        [Parameter(ValueFromPipelineByPropertyName)]
        [int]$SearchTimeout = 5,

        # If set, will force a rescan of the network.
        # Otherwise, the most recent cached result will be returned.
        [Parameter(ValueFromPipelineByPropertyName)]
        [switch]
        $Force,

        # The type of the device to find. By default, roku:ecp.
        # Changing this value is unlikely to find any Rokus, but you can see other devices with -Verbose.
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$DeviceType = 'roku:ecp'
    )

    begin {
        #region Embedded C# SSDP Finder
        if (-not ('StartAutomating.RokuFinder' -as [type])) {
Add-Type -TypeDefinition @'
namespace StartAutomating
{
    using System;
    using System.Net;
    using System.Net.Sockets;
    using System.Text;
    using System.Timers;
    using System.Collections.Generic;
 
    public class RokuFinder
    {
        public List<string> FindDevices(string deviceType = "roku:ecp", int searchTimeOut = 5)
        {
            List<string> results = new List<string>();
            const int MaxResultSize = 8096;
            const string MulticastIP = "239.255.255.250";
            const int multicastPort = 1900;
 
            byte[] multiCastData = Encoding.UTF8.GetBytes(string.Format(@"M-SEARCH * HTTP/1.1
HOST: {0}:{1}
MAN: ""ssdp:discover""
MX: {2}
ST: {3}
", MulticastIP, multicastPort, searchTimeOut, deviceType));
 
            Socket socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
            socket.SendBufferSize = multiCastData.Length;
            SocketAsyncEventArgs sendEvent = new SocketAsyncEventArgs();
            sendEvent.RemoteEndPoint = new IPEndPoint(IPAddress.Parse(MulticastIP), multicastPort);
            sendEvent.SetBuffer(multiCastData, 0, multiCastData.Length);
            sendEvent.Completed += (sender, e) => {
                if (e.SocketError != SocketError.Success) { return; }
 
                switch (e.LastOperation)
                {
                    case SocketAsyncOperation.SendTo:
                        // When the initial multicast is done, get ready to receive responses
                        e.RemoteEndPoint = new IPEndPoint(IPAddress.Any, 0);
                        byte[] receiveBuffer = new byte[MaxResultSize];
                        socket.ReceiveBufferSize = receiveBuffer.Length;
                        e.SetBuffer(receiveBuffer, 0, MaxResultSize);
                        socket.ReceiveFromAsync(e);
                        break;
 
                    case SocketAsyncOperation.ReceiveFrom:
                        // Got a response, so decode it
                        string result = Encoding.UTF8.GetString(e.Buffer, 0, e.BytesTransferred);
                        if (result.StartsWith("HTTP/1.1 200 OK", StringComparison.InvariantCultureIgnoreCase)) {
                            if (! results.Contains(result)) { results.Add(result); }
                        }
 
                        if (socket != null)// and kick off another read
                            socket.ReceiveFromAsync(e);
                        break;
                    default:
                        break;
                }
            };
 
            Timer t = new Timer(TimeSpan.FromSeconds(searchTimeOut + 1).TotalMilliseconds);
            t.Elapsed += (e, s) => { try { socket.Dispose(); socket = null; } catch {}};
 
            // Kick off the initial Send
            socket.SetSocketOption(SocketOptionLevel.IP,SocketOptionName.MulticastInterface, IPAddress.Parse(MulticastIP).GetAddressBytes());
            socket.SendToAsync(sendEvent);
            t.Start();
            DateTime endTime = DateTime.Now.AddSeconds(searchTimeOut);
            do {
                System.Threading.Thread.Sleep(100);
            } while (DateTime.Now < endTime);
            return results;
        }
    }
}
'@
        }
        #endregion Embedded C# SSDP Finder
    }

    process {
        # If -Force was sent, invalidate the cache
        if ($Force) { $script:CachedDiscoveredRokus = $null }
        if (-not $script:CachedDiscoveredRokus) { # If there is no cache, repopulate it.
            $script:CachedDiscoveredRokus =
                @([StartAutomating.RokuFinder]::new().FindDevices($DeviceType, $SearchTimeout)) |
                    Where-Object {
                        # Write all devices found to Verbose
                        Write-Verbose $_
                        $_ -like '*roku*' # but only pass down devices that could be rokus.
                    } |
                    ForEach-Object {
                        $headerLines = @($_ -split '\r\n') # Split the header lines

                        # The IPAddress will be within the Location: header
                        $ipAddress = $(
                            $(
                                $headerLines -like 'LOCATION:*' -replace '^Location:\s{1,}'
                            ) -as [uri] # We can force this into a URI
                        ).DnsSafeHost # At which point the DNSSafeHost will be the IP

                        # Just doing a quick sanity check here
                        # so we don't emit objects we can't accurately map the IP
                        if ($ipAddress -like '*.*') {
                            $friendlyName = Get-RokuDeviceName -IPAddress $ipAddress

                            [PSCustomObject][Ordered]@{
                                IPAddress = [IPAddress]$ipAddress

                                FriendlyName = $friendlyName

                                # The serial number is "easier": it's the last part of the USN header
                                SerialNumber = @($headerLines -like 'USN:*' -split ':')[-1]

                                # The Version is a little trickier: It's the first chunk in the SERVER:
                                # header after 'Roku/'
                                Version = @($headerLines -like 'SERVER:*' -split '[\s/]')[2]
                                PSTypeName = 'Roku.BasicInfo'
                            }
                        }
                    }
        }
        $script:CachedDiscoveredRokus # Output the cached value.
    }
}

# Find Roku devices
$rokuDevices = Find-Roku -Force

# Present the user with a selection dialog
$selectedRoku = $rokuDevices | Out-GridView -Title "Select a Roku Device" -PassThru

# If a device was selected, save its IP address to a file
if ($selectedRoku) {
    $selectedRoku.IPAddress.IPAddressToString | Out-File -NoNewline -Force -FilePath "RokuIP.txt"
    Write-Host "The IP address of the selected Roku device has been saved to RokuIP.txt"
}