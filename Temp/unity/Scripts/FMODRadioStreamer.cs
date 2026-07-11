using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using FMOD;
using FMODUnity;
using UnityEngine;
using UnityEngine.Networking;

public class FMODRadioStreamer : MonoBehaviour
{
    [Header("Audio Route Fix (Android)")]
    [Tooltip("Enable audio routing fix for devices that default to speaker after reboot (e.g., Moto G5 Plus)")]
    public bool enableAudioRouteFix = true;
    
    [Tooltip("Delay in seconds before applying audio route fix. Try 0 first, increase if needed for auto-start scenarios.")]
    [Range(0f, 10f)]
    public float audioRouteFixDelay = 0f;
    
    private string streamUrl = "";
    private bool isMuted = false;
    private FMOD.Sound sound;
    private FMOD.Channel channel;
    private FMOD.ChannelGroup masterChannelGroup;
    private FMOD.System system;
    private bool isPlaying = false;
    private bool isInitialized = false;
    private bool hasSound = false;
    private bool hasChannel = false;
    private bool wasPlayingBeforePause = false;
    
    public System.Action<bool> OnMuteStateChanged;
    
    void Update()
    {
        // Update FMOD system
        if (isInitialized)
        {
            try
            {
                system.update();
            }
            catch (Exception e)
            {
                UnityEngine.Debug.LogError("FMOD update error: " + e.Message);
            }
        }
    }

    void OnDestroy()
    {
        StopStream();
    }
    
    void OnApplicationQuit()
    {
        // App is being quit - ensure complete cleanup
        StopStream();
    }
    
    void OnApplicationPause(bool pauseStatus)
    {
#if !UNITY_EDITOR
        if (pauseStatus)
        {
            // App is being paused (screen locked, switched to another app, etc.)
            // Stop stream to save bandwidth and prevent stale buffers
            wasPlayingBeforePause = isPlaying;
            if (isPlaying)
            {
                UnityEngine.Debug.Log("App paused - stopping stream to save bandwidth");
                StopStream();
            }
        }
        else
        {
            // App is resuming
            // Restart stream if it was playing before pause
            if (wasPlayingBeforePause)
            {
                UnityEngine.Debug.Log("App resumed - restarting stream");
                PlayStream();
                wasPlayingBeforePause = false;
            }
        }
#endif
    }

    void InitializeFMOD()
    {
        try
        {
            // Get FMOD system from RuntimeManager
            system = RuntimeManager.CoreSystem;
            system.getMasterChannelGroup(out masterChannelGroup);
            isInitialized = true;
            UnityEngine.Debug.Log("FMOD initialized successfully");
        }
        catch (Exception e)
        {
            UnityEngine.Debug.LogError("Failed to initialize FMOD: " + e.Message);
            isInitialized = false;
        }
    }


    public void PlayStream(string url)
    {
        if (isPlaying)
        {
            StopStream();
        }
        streamUrl = url;
        PlayStream();
    }

    void PlayStream()
    {

        if (!isInitialized)
        {
            InitializeFMOD();
            if (!isInitialized)
            {
                UnityEngine.Debug.LogError("Failed to initialize FMOD");
                return;
            }
        }
        
        if (isPlaying)
        {
            StopStream();
        }
        
        if (string.IsNullOrEmpty(streamUrl))
        {
            UnityEngine.Debug.LogError("No stream URL provided");
            return;
        }
        
        StartCoroutine(ApplyAudioRouteFixAndPlay());
    }
    
    IEnumerator ApplyAudioRouteFixAndPlay()
    {
        if (enableAudioRouteFix)
        {
            if (audioRouteFixDelay > 0f)
            {
                UnityEngine.Debug.Log($"Waiting {audioRouteFixDelay}s before applying audio route fix...");
                yield return new WaitForSeconds(audioRouteFixDelay);
            }
            
            AudioRouteFixer.RetriggerAudioRouting();
        }
        
        string resolvedUrl = null;
        yield return StartCoroutine(ResolveStreamUrlCoroutine(streamUrl, value => resolvedUrl = value));
        if (resolvedUrl == null)
        {
            UnityEngine.Debug.LogError("Failed to resolve stream URL");
            yield break;
        }
        yield return StartCoroutine(LoadAndPlayStream(resolvedUrl));
    }

    IEnumerator LoadAndPlayStream(string resolvedUrl)
    {
        UnityEngine.Debug.Log("Loading stream: " + resolvedUrl);
        
        // Create sound from URL
        FMOD.CREATESOUNDEXINFO exinfo = new FMOD.CREATESOUNDEXINFO();
        exinfo.cbsize = Marshal.SizeOf(typeof(FMOD.CREATESOUNDEXINFO));
        exinfo.suggestedsoundtype = FMOD.SOUND_TYPE.MPEG;

        FMOD.MODE createMode = MODE.CREATESTREAM | MODE.NONBLOCKING;

        FMOD.RESULT result = system.createSound(resolvedUrl, 
            createMode, 
            ref exinfo,
            out sound);
        
        UnityEngine.Debug.Log("CreateSound result: " + result);
        
        if (result != FMOD.RESULT.OK)
        {
            UnityEngine.Debug.LogError("Failed to create sound: " + result);
            hasSound = false;
            // Clean up any partial sound creation
            if (sound.handle != System.IntPtr.Zero)
            {
                sound.release();
            }
            yield break;
        }
        
        hasSound = true;
        
        // Wait for sound to load
        float timeout = 15f;
        float elapsed = 0f;
        while (true)
        {
            FMOD.RESULT openStateResult = sound.getOpenState(out OPENSTATE openState, out _, out _, out _);

            if (openStateResult == FMOD.RESULT.ERR_NOTREADY)
            {
                // Still loading asynchronously, keep waiting.
            }
            else if (openStateResult != FMOD.RESULT.OK)
            {
                UnityEngine.Debug.LogWarning("Failed to query sound open state: " + openStateResult);
                break;
            }

            if (elapsed >= timeout)
            {
                UnityEngine.Debug.LogError("Loading timeout after " + timeout + " seconds");
                if (hasSound)
                {
                    sound.release();
                    hasSound = false;
                }
                yield break;
            }
            
            if (openState == OPENSTATE.READY)
            {
                UnityEngine.Debug.Log("Stream loaded successfully!");
                break;
            }
            
            if (openState == OPENSTATE.ERROR)
            {
                UnityEngine.Debug.LogWarning("Stream loading error at " + elapsed + " seconds");
            }
            
            elapsed += Time.deltaTime;
            yield return null;
        }

        // Play the sound
        result = system.playSound(sound, masterChannelGroup, false, out channel);
        
        if (result == FMOD.RESULT.OK)
        {
            channel.setPriority(0);
            hasChannel = true;
            isPlaying = true;
            isMuted = false;
            UnityEngine.Debug.Log("Stream started successfully");
            OnMuteStateChanged?.Invoke(isMuted);
            
        }
        else
        {
            UnityEngine.Debug.LogError("Failed to play: " + result);
            hasChannel = false;
        }
    }

    IEnumerator ResolveStreamUrlCoroutine(string url, Action<string> onComplete)
    {
        string resolvedUrl = url;
        UnityEngine.Debug.Log("Trying to resolve stream URL: " + resolvedUrl);
        const int maxSteps = 5; // max number of redirects

        for (int step = 0; step < maxSteps; step++)
        {
            using (UnityWebRequest www = UnityWebRequest.Get(resolvedUrl))
            {
                www.redirectLimit = 0;
                www.disposeDownloadHandlerOnDispose = true;
                www.disposeUploadHandlerOnDispose = true;
                www.timeout = 10;

                // Set headers to mimic a browser
                www.SetRequestHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36");
                www.SetRequestHeader("Accept", "audio/*");
                www.SetRequestHeader("Accept-Encoding", "identity");

                var operation = www.SendWebRequest();

                float timeoutWindow = 10f;
                float elapsed = 0f;

                while (!operation.isDone && elapsed < timeoutWindow && www.responseCode == 0)
                {
                    elapsed += Time.deltaTime;
                    yield return null;
                }

                bool timedOutWaitingForHeaders = !operation.isDone && www.responseCode == 0;
                if (timedOutWaitingForHeaders)
                {
                    UnityEngine.Debug.LogWarning("ResolveStreamUrlCoroutine timed out before headers for " + resolvedUrl);
                    www.Abort();
                    break;
                }

                if (!operation.isDone && www.responseCode > 0)
                {
                    // headers received no further download needed
                    www.Abort();
                }
                else
                {
                    yield return operation;
                }

                long responseCode = www.responseCode;
                bool isSuccessStatus = responseCode >= 200 && responseCode < 300;

                UnityEngine.Debug.Log("Response code: " + responseCode);
                UnityEngine.Debug.Log("Result: " + www.result);
                UnityEngine.Debug.Log("Error: " + www.error);

                // redirect response code
                if (responseCode >= 300 && responseCode < 400)
                {
                    string location = www.GetResponseHeader("Location");
                    if (!string.IsNullOrEmpty(location))
                    {
                        resolvedUrl = MakeAbsoluteUrl(resolvedUrl, location);
                        continue;
                    }

                    UnityEngine.Debug.LogWarning("Redirect response had no Location header for " + resolvedUrl);
                    break;
                }

                // successful response
                if (isSuccessStatus)
                {
                    string contentType = www.GetResponseHeader("Content-Type");
                    string contentDisposition = www.GetResponseHeader("Content-Disposition");
                    if (IsPlaylistResponse(contentType, contentDisposition, resolvedUrl))
                    {
                        string playlistBody = www.downloadHandler != null ? www.downloadHandler.text : null;
                        string playlistUrl = ParsePlaylistForFirstUrl(playlistBody, resolvedUrl);

                        if (!string.IsNullOrEmpty(playlistUrl))
                        {
                            resolvedUrl = playlistUrl;
                            continue;
                        }

                        UnityEngine.Debug.LogWarning("Playlist did not contain a playable URL for " + resolvedUrl);
                    }

                    // Successful non-playlist response, exit loop.
                }
                else if (responseCode != 0)
                {
                    UnityEngine.Debug.LogWarning("ResolveStreamUrlCoroutine encountered error " + www.error + " for " + resolvedUrl);
                }

                break;
            }
        }

        UnityEngine.Debug.Log("Resolved URL: " + resolvedUrl);
        onComplete?.Invoke(resolvedUrl);
        yield break;
    }

    private static string MakeAbsoluteUrl(string currentUrl, string location)
    {
        try
        {
            Uri baseUri = new Uri(currentUrl);
            Uri resultUri = new Uri(baseUri, location);
            return resultUri.AbsoluteUri;
        }
        catch (Exception e)
        {
            UnityEngine.Debug.LogWarning("Failed to build absolute URL from " + currentUrl + " and " + location + ": " + e.Message);
            return location;
        }
    }

    private static bool IsPlaylistResponse(string contentType, string contentDisposition, string requestUrl)
    {
        if (string.IsNullOrEmpty(contentType))
        {
            contentType = string.Empty;
        }

        string normalized = contentType.ToLowerInvariant();

        bool typeMatches = normalized.Contains("audio/x-mpegurl") ||
               normalized.Contains("application/vnd.apple.mpegurl") ||
               normalized.Contains("application/mpegurl") ||
               normalized.Contains("audio/mpegurl") ||
               normalized.Contains("audio/x-scpls") ||
               normalized.Contains("application/pls") ||
               normalized.Contains("audio/pls") ||
               normalized.Contains("text/plain") ||
               normalized.Contains("application/force-download");

        bool dispositionMatches = false;
        if (!string.IsNullOrEmpty(contentDisposition))
        {
            string normalizedDisposition = contentDisposition.ToLowerInvariant();
            dispositionMatches = normalizedDisposition.Contains(".m3u") ||
                                 normalizedDisposition.Contains(".m3u8") ||
                                 normalizedDisposition.Contains(".pls");
        }

        bool urlMatches = !string.IsNullOrEmpty(requestUrl) &&
                          (requestUrl.EndsWith(".m3u", StringComparison.OrdinalIgnoreCase) ||
                           requestUrl.EndsWith(".m3u8", StringComparison.OrdinalIgnoreCase) ||
                           requestUrl.EndsWith(".pls", StringComparison.OrdinalIgnoreCase));

        return typeMatches || dispositionMatches || urlMatches;
    }

    private static string ParsePlaylistForFirstUrl(string playlistBody, string baseUrl)
    {
        if (string.IsNullOrEmpty(playlistBody))
        {
            return null;
        }

        string[] lines = playlistBody.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
        List<string> candidates = new List<string>();

        foreach (string rawLine in lines)
        {
            string line = rawLine.Trim();

            if (string.IsNullOrEmpty(line))
            {
                continue;
            }

            if (line.StartsWith("#"))
            {
                continue;
            }

            if (line.StartsWith("[") && line.EndsWith("]"))
            {
                // Section headers in .pls files (e.g., [playlist]) are not URLs.
                continue;
            }

            if (line.StartsWith("File", StringComparison.OrdinalIgnoreCase))
            {
                int equalsIndex = line.IndexOf('=');
                if (equalsIndex >= 0 && equalsIndex < line.Length - 1)
                {
                    candidates.Add(line.Substring(equalsIndex + 1).Trim());
                }
            }
            else if (!line.Contains("="))
            {
                candidates.Add(line);
            }
        }

        foreach (string candidate in candidates)
        {
            if (Uri.IsWellFormedUriString(candidate, UriKind.Absolute))
            {
                return candidate;
            }

            if (!string.IsNullOrEmpty(baseUrl))
            {
                try
                {
                    Uri baseUri = new Uri(baseUrl);
                    Uri resultUri = new Uri(baseUri, candidate);
                    return resultUri.AbsoluteUri;
                }
                catch (Exception e)
                {
                    UnityEngine.Debug.LogWarning("Failed to resolve relative playlist entry " + candidate + " against " + baseUrl + ": " + e.Message);
                }
            }
        }

        return null;
    }

    public void ToggleMuteStream()
    {
        if (isMuted)
        {
            /*
            WriteChannelState("before setMute(false)");
            FMOD.RESULT muteResult = channel.setMute(false);
            UnityEngine.Debug.Log("setMute(false) result: " + muteResult);
            WriteChannelState("after setMute(false)");
            */
            PlayStream();
            isMuted = false;
            UnityEngine.Debug.Log("Stream restarted");
        }
        else
        {
            /*
            WriteChannelState("before setMute(true)");
            FMOD.RESULT muteResult = channel.setMute(true);
            UnityEngine.Debug.Log("setMute(true) result: " + muteResult);
            WriteChannelState("after setMute(true)");
            */
            StopStream();
            isMuted = true;
            UnityEngine.Debug.Log("Stream stopped");
        }
        OnMuteStateChanged?.Invoke(isMuted);
    }

    public void StopStream()
    {
        if (hasChannel)
        {
            channel.stop();
            hasChannel = false;
            UnityEngine.Debug.Log("Channel stopped");
        }

        if (hasSound)
        {
            sound.release();
            hasSound = false;
            UnityEngine.Debug.Log("Sound released");
        }

        isPlaying = false;
    }
    
    
    public bool IsMuted()
    {
        return isMuted;
    }
    
    private void WriteChannelState(string context)
    {
        channel.isPlaying(out bool playing);
        channel.getPaused(out bool paused);
        channel.isVirtual(out bool isVirtual);
        UnityEngine.Debug.Log("Channel " + context + ": isPlaying=" + playing + ", getPaused=" + paused + ", isVirtual=" + isVirtual);
    }
    
}
