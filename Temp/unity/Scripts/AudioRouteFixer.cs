using UnityEngine;

/// <summary>
/// Bridge to Android Java plugin that forces audio routing re-evaluation.
/// Fixes issue on Moto G5 Plus where audio defaults to speaker even with headphone jack plugged in after reboot.
/// </summary>
public static class AudioRouteFixer
{
#if UNITY_ANDROID && !UNITY_EDITOR
    /// <summary>
    /// Forces Android to re-evaluate audio routing by triggering AudioManager and playing brief silence.
    /// Safe to call multiple times.
    /// </summary>
    public static void RetriggerAudioRouting()
    {
        try
        {
            using (AndroidJavaClass unityPlayer = new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
            using (AndroidJavaObject activity = unityPlayer.GetStatic<AndroidJavaObject>("currentActivity"))
            using (AndroidJavaClass fixer = new AndroidJavaClass("nl.siwoc.internetradio.AudioRouteFixer"))
            {
                fixer.CallStatic("retriggerAudioRouting", activity);
                Debug.Log("AudioRouteFixer: Audio routing retriggered successfully");
            }
        }
        catch (System.Exception e)
        {
            Debug.LogWarning("AudioRouteFixer failed: " + e.Message);
        }
    }
#else
    /// <summary>
    /// No-op on non-Android platforms
    /// </summary>
    public static void RetriggerAudioRouting() 
    { 
        Debug.Log("AudioRouteFixer: Skipped (not on Android device)");
    }
#endif
}

