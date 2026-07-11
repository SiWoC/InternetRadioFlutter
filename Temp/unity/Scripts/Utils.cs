using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;

public class Utils
{

    static bool IsPrivateIP(IPAddress ip)
    {
        byte[] bytes = ip.GetAddressBytes();

        // 10.0.0.0 - 10.255.255.255
        if (bytes[0] == 10)
        {
            return true;
        }

        // 172.16.0.0 - 172.31.255.255
        if (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31)
        {
            return true;
        }

        // 192.168.0.0 - 192.168.255.255
        if (bytes[0] == 192 && bytes[1] == 168)
        {
            return true;
        }

        return false;
    }

    public static string GetLocalIPAddress()
    {
        try
        {
            string fallbackIP = null;

            // Get all network interfaces
            NetworkInterface[] interfaces = NetworkInterface.GetAllNetworkInterfaces();
            foreach (NetworkInterface ni in interfaces)
            {
                // Check if interface is up and not loopback
                if (ni.OperationalStatus == OperationalStatus.Up &&
                    ni.NetworkInterfaceType != NetworkInterfaceType.Loopback)
                {
                    IPInterfaceProperties properties = ni.GetIPProperties();
                    foreach (UnicastIPAddressInformation ip in properties.UnicastAddresses)
                    {
                        // Look for IPv4 address that's private (local network)
                        if (ip.Address.AddressFamily == AddressFamily.InterNetwork &&
                            !IPAddress.IsLoopback(ip.Address) &&
                            IsPrivateIP(ip.Address))
                        {
                            string ipString = ip.Address.ToString();

                            // Prefer 192.168.x.x (typical home network) or WiFi interface
                            if (ipString.StartsWith("192.168.") ||
                                ni.NetworkInterfaceType == NetworkInterfaceType.Wireless80211)
                            {
                                return ipString;
                            }

                            // Keep 10.x.x.x or 172.x.x.x as fallback
                            if (fallbackIP == null)
                            {
                                fallbackIP = ipString;
                            }
                        }
                    }
                }
            }

            return fallbackIP ?? "No IP";
        }
        catch (System.Exception e)
        {
            Debug.LogWarning($"Failed to get IP address: {e.Message}");
            return "IP unavailable";
        }
    }
}

