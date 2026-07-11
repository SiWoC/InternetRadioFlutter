using System.Net;
using UnityEngine;

public static class Settings
{

    public enum OperatingMode
    {
        Player,
        Remote
    }

    private const string PREF_CURRENT_STATION = "CurrentStation";
    private const string PREF_OPERATING_MODE = "OperatingMode"; // Player or Remote
    private const string PREF_PLAYER_IPADDRESS = "PlayerIPAddress";
    private const string PREF_TESTURL = "TestURL";

    public static string GetCurrentStationName()
    {
        return PlayerPrefs.GetString(PREF_CURRENT_STATION);
    }

    public static void SetCurrentStationName(string currentStation)
    {
        if (currentStation != null && currentStation != "")
        {
            PlayerPrefs.SetString(PREF_CURRENT_STATION, currentStation);
        }
        PlayerPrefs.Save();
    }

    public static OperatingMode GetOperatingMode()
    {
        return (OperatingMode)PlayerPrefs.GetInt(PREF_OPERATING_MODE, 0);
    }

    public static void SetOperatingMode(OperatingMode operatingMode)
    {
        Debug.Log("Setting operatingmode to: " +  operatingMode);
        PlayerPrefs.SetInt(PREF_OPERATING_MODE, (int)operatingMode);
        PlayerPrefs.Save();
    }

    public static string GetPlayerIPAddress()
    {
        return PlayerPrefs.GetString(PREF_PLAYER_IPADDRESS, "");
    }

    public static void SetPlayerIPAddress(string ipAddress)
    {
        if (ipAddress != null && ipAddress != "")
        {
            PlayerPrefs.SetString(PREF_PLAYER_IPADDRESS, ipAddress);
        }
        PlayerPrefs.Save();
    }

    public static string GetTestURL()
    {
        return PlayerPrefs.GetString(PREF_TESTURL, "");
    }

    public static void SetTestURL(string testURL)
    {
        if (testURL != null && testURL != "")
        {
            PlayerPrefs.SetString(PREF_TESTURL, testURL);
        }
        PlayerPrefs.Save();
    }

}
