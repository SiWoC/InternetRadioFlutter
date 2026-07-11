using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Networking;

public class StreamAnalyzer : MonoBehaviour
{
    [Header("Test URLs")]
    private string[] testUrls = {
        "https://live-radio01.mediahubaustralia.com/2TJW/mp3/"
    };
    
    void Start()
    {
        StartCoroutine(AnalyzeAllStreams());
    }
    
    IEnumerator AnalyzeAllStreams()
    {
        yield return new WaitForSeconds(5f);
        foreach (string url in testUrls)
        {
            yield return StartCoroutine(AnalyzeStream(url));
            yield return new WaitForSeconds(1f); // Pause between requests
        }
    }
    
    IEnumerator AnalyzeStream(string url)
    {
        Log("=== ANALYZING: " + url + " ===");
        
        using (UnityWebRequest www = UnityWebRequest.Get(url))
        {
            // Set headers to mimic a browser
            www.SetRequestHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36");
            www.SetRequestHeader("Accept", "audio/*");
            www.SetRequestHeader("Accept-Encoding", "identity");
            www.SetRequestHeader("Connection", "keep-alive");
            
            var operation = www.SendWebRequest();
            
            // Wait for response headers (first 5 seconds)
            float timeout = 15f;
            float elapsed = 0f;
            
            while (!operation.isDone && elapsed < timeout)
            {
                elapsed += Time.deltaTime;
                yield return null;
            }
            
            if (www.result == UnityWebRequest.Result.Success)
            {
                Log("✓ Connection successful");
                Log("Response Code: " + www.responseCode);
                
                // Analyze headers
                Log("=== RESPONSE HEADERS ===");
                foreach (var header in www.GetResponseHeaders())
                {
                    Log(header.Key + ": " + header.Value);
                }
                
                // Check content type
                string contentType = www.GetResponseHeader("Content-Type");
                if (!string.IsNullOrEmpty(contentType))
                {
                    Log("Content-Type: " + contentType);
                }
                
                // Check content length
                string contentLength = www.GetResponseHeader("Content-Length");
                if (!string.IsNullOrEmpty(contentLength))
                {
                    Log("Content-Length: " + contentLength);
                }
                else
                {
                    Log("Content-Length: Not specified (streaming)");
                }
                
                // Check transfer encoding
                string transferEncoding = www.GetResponseHeader("Transfer-Encoding");
                if (!string.IsNullOrEmpty(transferEncoding))
                {
                    Log("Transfer-Encoding: " + transferEncoding);
                }
                
                // Check server
                string server = www.GetResponseHeader("Server");
                if (!string.IsNullOrEmpty(server))
                {
                    Log("Server: " + server);
                }
                
                // Check icecast/shoutcast headers
                string icyName = www.GetResponseHeader("icy-name");
                if (!string.IsNullOrEmpty(icyName))
                {
                    Log("ICY-Name: " + icyName);
                }
                
                string icyGenre = www.GetResponseHeader("icy-genre");
                if (!string.IsNullOrEmpty(icyGenre))
                {
                    Log("ICY-Genre: " + icyGenre);
                }
                
                string icyBr = www.GetResponseHeader("icy-br");
                if (!string.IsNullOrEmpty(icyBr))
                {
                    Log("ICY-BR: " + icyBr);
                }
                
                // Analyze first few bytes
                byte[] data = www.downloadHandler.data;
                if (data != null && data.Length > 0)
                {
                    Log("=== STREAM ANALYSIS ===");
                    Log("Data received: " + data.Length + " bytes");
                    
                    // Check for common audio format signatures
                    if (data.Length >= 4)
                    {
                        string signature = System.Text.Encoding.ASCII.GetString(data, 0, Math.Min(4, data.Length));
                        Log("First 4 bytes: " + BitConverter.ToString(data, 0, Math.Min(4, data.Length)));
                        Log("ASCII signature: " + signature);
                        
                        // Check for MP3 signature
                        if (data.Length >= 2 && data[0] == 0xFF && (data[1] & 0xE0) == 0xE0)
                        {
                            Log("✓ MP3 signature detected");
                        }
                        // Check for AAC signature
                        else if (data.Length >= 4 && data[0] == 0xFF && (data[1] & 0xF0) == 0xF0)
                        {
                            Log("✓ AAC signature detected");
                        }
                        // Check for OGG signature
                        else if (data.Length >= 4 && data[0] == 0x4F && data[1] == 0x67 && data[2] == 0x67 && data[3] == 0x53)
                        {
                            Log("✓ OGG signature detected");
                        }
                        else
                        {
                            Log("? Unknown audio format signature");
                        }
                    }
                }
                else
                {
                    Log("✗ No data received");
                }
            }
            else
            {
                Log("✗ Connection failed: " + www.error + " " + www.result);
                Log("Response Code: " + www.responseCode);
            }
        }
        
        Log("=== ANALYSIS COMPLETE ===");
    }
    
    void Log(string message)
    {
        string timestamp = DateTime.Now.ToString("HH:mm:ss.fff");
        string logMessage = "[" + timestamp + "] " + message;
        
        UnityEngine.Debug.Log(logMessage);
        
    }
}
