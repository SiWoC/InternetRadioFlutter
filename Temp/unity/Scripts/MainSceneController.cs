using UnityEngine;
using UnityEngine.UI;
using TMPro;
using UnityEngine.InputSystem;
using System.Collections.Generic;

[System.Serializable]
public class SettingsData
{
    public RadioStation[] station;
}

public class MainSceneController : MonoBehaviour
{
    [Header("Canvas")]
    public Canvas uiCanvas;

    [Header("Main Panel")]
    public Button muteButton;
    public GameObject muteButtonPlaying;
    public GameObject muteButtonMuted;
    public GameObject remoteButton;
    public GameObject playerButton;
    public TextMeshProUGUI stationNameText;
    public RectTransform stationScrollView;
    public Transform stationListParent;
    public GameObject stationButtonPrefab;
    public TextMeshProUGUI ipAddressText;

    [Header("Settings Panel")]
    public GameObject settingsPanel;
    public TMP_InputField playerIPAddressInputField;
    public TextMeshProUGUI settingsPlayerConnectionTestResultText;
    public TMP_InputField settingsURLToTestInputField;

    [Header("Components")]
    public FMODRadioStreamer radioStreamer;
    public ScreensaverController screensaverController;
    public NetworkManager networkManager;

    private CanvasScaler canvasScaler;
    private List<RadioStation> radioStations = new List<RadioStation>();
    private int currentStationIndex = 0;
    private float statePollTimer = 0f;
    private const float STATE_POLL_INTERVAL = 2.5f; // seconds
    private bool isRemoteMode = false;
    private int currentWidth;
    private int currentHeight;

    void Awake()
    {
        SetupStations();
        SetupMuteButton();
    }
    
    void Start()
    {
        canvasScaler = uiCanvas.GetComponent<CanvasScaler>();
        currentWidth = Screen.width;
        currentHeight = Screen.height;
        UpdateLayoutForOrientation();        
        
        CreateStationButtons(); // also sets currentStationIndex
        settingsPanel.SetActive(false);

        if (Settings.GetOperatingMode() == Settings.OperatingMode.Player)
        {
            Screen.sleepTimeout = SleepTimeout.NeverSleep;
            remoteButton.SetActive(true);
            playerButton.SetActive(false);
            isRemoteMode = false;
            
            // Start TCP listener for remote control
            networkManager.StartListener();
            SetupNetworkCallbacks();
            
            if (radioStations.Count > 0)
            {
                SelectStation(currentStationIndex);
            }
        } else
        {
            remoteButton.SetActive(false);
            playerButton.SetActive(true);
            isRemoteMode = true;
            
            // Immediately poll for initial state from player
            if (!string.IsNullOrEmpty(Settings.GetPlayerIPAddress()))
            {
                PollPlayerState();
            }
        }

        ipAddressText.text = Utils.GetLocalIPAddress();
    }
    
    void SetupStations()
    {
        // Load stations from JSON file
        TextAsset jsonFile = Resources.Load<TextAsset>("settings");
        if (jsonFile != null)
        {
            try
            {
                // Parse the JSON data
                var settingsData = JsonUtility.FromJson<SettingsData>(jsonFile.text);
                
                // Clear existing stations
                radioStations.Clear();
                
                // Add stations from JSON directly
                foreach (var station in settingsData.station)
                {
                    radioStations.Add(station);
                }
                
                Debug.Log($"Loaded {radioStations.Count} stations from settings.json");
            }
            catch (System.Exception e)
            {
                Debug.LogError($"Failed to parse settings.json: {e.Message}");
                SetupFallbackStations();
            }
        }
        else
        {
            Debug.LogWarning("settings.json not found in Resources folder, using fallback stations");
            SetupFallbackStations();
        }
    }
    
    void SetupFallbackStations()
    {
        // Fallback stations if JSON loading fails
        radioStations.Add(new RadioStation
        {
            name = "ABC Triple J NSW",
            url = "https://live-radio01.mediahubaustralia.com/2TJW/mp3/"
        });
        
        radioStations.Add(new RadioStation
        {
            name = "Q-Music",
            url = "https://stream.qmusic.nl/qmusic/mp3"
        });
        
        radioStations.Add(new RadioStation
        {
            name = "Radio 538",
            url = "https://playerservices.streamtheworld.com/api/livestream-redirect/RADIO538.mp3"
        });
    }
    
    void CreateStationButtons()
    {
        // Clear existing buttons
        foreach (Transform child in stationListParent)
        {
            Destroy(child.gameObject);
        }

        // Create buttons for each station
        for (int i = 0; i < radioStations.Count; i++)
        {
            int stationIndex = i; // Capture for usage in SelectStation lambda
            GameObject buttonObj = Instantiate(stationButtonPrefab, stationListParent);
            Button button = buttonObj.GetComponent<Button>();
            TextMeshProUGUI buttonText = buttonObj.GetComponentInChildren<TextMeshProUGUI>();
            UnityEngine.UI.Image buttonImage = buttonObj.GetComponent<UnityEngine.UI.Image>();
            
            // Try to load station image
            Sprite stationSprite = CreateStationSprite(radioStations[i]);
            if (stationSprite != null)
            {
                buttonImage.sprite = stationSprite;
                // Hide text when image is available
                buttonText.gameObject.SetActive(false);
            }
            else
            {
                // Image not found or no image path, use text
                buttonText.text = radioStations[i].name;
                buttonText.gameObject.SetActive(true);
            }
            
            button.onClick.AddListener(() => SelectStation(stationIndex));

            if (radioStations[i].name == Settings.GetCurrentStationName())
            {
                currentStationIndex = i;
            }
        }
        
        // Force content to be wide enough for horizontal scrolling
        EnsureContentWidthForScrolling();
    }
    
    void SelectStation(int stationIndex)
    {
        if (stationIndex < 0 || stationIndex >= radioStations.Count) return;

        currentStationIndex = stationIndex;
        
        // In Remote mode, send command to Player
        if (isRemoteMode)
        {
            if (currentStationIndex == radioStations.Count - 1)
            {
                SendCommandToPlayer($"TESTURL|{radioStations[radioStations.Count - 1].url}");
            }
            else
            {
                SendCommandToPlayer($"SELECT_STATION|{stationIndex}");
            }
        }
        else
        {
            // In Player mode, play locally
            radioStreamer.PlayStream(radioStations[currentStationIndex].url);
            Settings.SetCurrentStationName(radioStations[currentStationIndex].name);
            
            // Update screensaver with current station image
            UpdateScreensaverStationImage();
        }
    }

    public void ToggleMute()
    {
        if (isRemoteMode)
        {
            // In Remote mode, send command to Player
            bool currentlyMuted = muteButtonMuted.activeSelf;
            string command = currentlyMuted ? "UNMUTE" : "MUTE";
            SendCommandToPlayer(command);
            
            // Optimistically update UI (will be synced on next poll)
            UpdateMuteButton(!currentlyMuted);
        }
        else
        {
            // In Player mode, toggle locally
            radioStreamer.ToggleMuteStream();
        }
    }
    
    void SetupMuteButton()
    {
        // Subscribe to mute state changes
        radioStreamer.OnMuteStateChanged += UpdateMuteButton;
        
        // Set initial button text
        UpdateMuteButton(radioStreamer.IsMuted());
    }
    
    void UpdateMuteButton(bool isMuted)
    {
        muteButtonMuted.SetActive(isMuted);
        muteButtonPlaying.SetActive(!isMuted);
    }
    
    void Update()
    {
        if (Screen.width != currentWidth || Screen.height != currentHeight)
        {
            currentWidth = Screen.width;
            currentHeight = Screen.height;
            UpdateLayoutForOrientation();
        }

        if (radioStations.Count > 0 && !isRemoteMode)
        {
            stationNameText.text = radioStations[currentStationIndex].name;
        }
        
        DetectUITouch();
        
        // Poll for state updates in Remote mode
        if (isRemoteMode && !string.IsNullOrEmpty(Settings.GetPlayerIPAddress()))
        {
            statePollTimer += Time.deltaTime;
            if (statePollTimer >= STATE_POLL_INTERVAL)
            {
                statePollTimer = 0f;
                
                // Only poll if screensaver is not active
                if (!screensaverController.IsScreensaverActive())
                {
                    PollPlayerState();
                }
            }
        }
    }
    
    void DetectUITouch()
    {
        
        // Check for touch input (Android) using new Input System
        if (Touchscreen.current != null && Touchscreen.current.touches.Count > 0)
        {
            var touch = Touchscreen.current.touches[0];
            if (touch.press.wasPressedThisFrame)
            {
                screensaverController.ResetTimer();
            }
        }
        
        // Check for mouse input (editor/desktop testing) using new Input System
        if (Mouse.current != null && Mouse.current.leftButton.wasPressedThisFrame)
        {
            screensaverController.ResetTimer();
        }
    }
    
    Sprite CreateStationSprite(RadioStation station)
    {
        if (string.IsNullOrEmpty(station.image))
        {
            return null;
        }
        
        // Remove leading slash if present for Resources.Load
        string imagePath = station.image.StartsWith("/") ? 
            station.image.Substring(1) : station.image;
        
        // Remove .png extension for Resources.Load
        if (imagePath.EndsWith(".png"))
        {
            imagePath = imagePath.Substring(0, imagePath.Length - 4);
        }
        
        Texture2D stationTexture = Resources.Load<Texture2D>(imagePath);
        if (stationTexture != null)
        {
            // Convert texture to sprite
            return Sprite.Create(stationTexture, 
                new Rect(0, 0, stationTexture.width, stationTexture.height), 
                new Vector2(0.5f, 0.5f));
        }
        
        return null;
    }
    
    void UpdateScreensaverStationImage()
    {
        Sprite stationSprite = CreateStationSprite(radioStations[currentStationIndex]);
        screensaverController.SetStationImage(stationSprite);
    }

    public void OnRemote()
    {
        // No ip-address yet configured?
        if (Settings.GetPlayerIPAddress().Length == 0)
        {
            OnSettings();
            return;
        }

        // Switch to Remote mode (test connection async)
        SwitchToRemoteModeAsync();
    }
    
    async void SwitchToRemoteModeAsync()
    {
        // Test connection first
        bool connected = await networkManager.TestConnection(Settings.GetPlayerIPAddress());
        
        if (!connected)
        {
            Debug.LogWarning("Cannot connect to player, opening settings");
            OnSettings();
            return;
        }

        // switching from being the Player to being the Remote
        Settings.SetOperatingMode(Settings.OperatingMode.Remote);
        Screen.sleepTimeout = SleepTimeout.SystemSetting;
        remoteButton.SetActive(false);
        playerButton.SetActive(true);
        radioStreamer.StopStream();
        isRemoteMode = true;
        
        // Stop listener if it was running
        networkManager.StopListener();
        
        // Immediately poll for initial state
        PollPlayerState();
    }

    public void OnPlayer()
    {
        // switching from being the Remote to being the Player
        Settings.SetOperatingMode(Settings.OperatingMode.Player);
        Screen.sleepTimeout = SleepTimeout.NeverSleep;
        remoteButton.SetActive(true);
        playerButton.SetActive(false);
        isRemoteMode = false;
        
        // Stop any remote polling
        statePollTimer = 0f;
        
        // Start listening for remote commands
        networkManager.StartListener();
        SetupNetworkCallbacks();
        
        if (radioStations.Count > 0)
        {
            SelectStation(currentStationIndex);
        }
    }

    public void OnSettings()
    {
        playerIPAddressInputField.text = Settings.GetPlayerIPAddress();
        settingsURLToTestInputField.text = Settings.GetTestURL();
        settingsPlayerConnectionTestResultText.text = "";
        settingsPanel.SetActive(true);
    }

    public void OnSettingsPlayerConnectionTest()
    {
        TestConnectionToPlayerAsync();
    }

    public void OnSettingsURLTest()
    {
        Settings.SetTestURL(settingsURLToTestInputField.text);
        radioStations[radioStations.Count - 1].url = settingsURLToTestInputField.text;
        SelectStation(radioStations.Count - 1);
    }

    async void TestConnectionToPlayerAsync()
    {
        string playerIP = playerIPAddressInputField.text;
        if (string.IsNullOrEmpty(playerIP))
        {
            Debug.LogWarning("No player IP address provided");
            settingsPlayerConnectionTestResultText.text = "Error: No IP";
            return;
        }
        
        settingsPlayerConnectionTestResultText.text = "Testing...";
        
        bool result = await networkManager.TestConnection(playerIP);
        
        if (result)
        {
            settingsPlayerConnectionTestResultText.text = "OK";
            Settings.SetPlayerIPAddress(playerIP);
        }
        else
        {
            settingsPlayerConnectionTestResultText.text = "Error";
        }
    }

    public void OnSettingsBack()
    {
        Settings.SetPlayerIPAddress(playerIPAddressInputField.text);
        Settings.SetTestURL(settingsURLToTestInputField.text);
        settingsPanel.SetActive(false);
    }

    public void OnExit()
    {
        Debug.Log("Quitting");
#if UNITY_EDITOR
        UnityEditor.EditorApplication.isPlaying = false;
#else
        Application.Quit(); 
#endif
    }
    
    void SetupNetworkCallbacks()
    {
        // Setup callbacks for when network commands are received (Player mode)
        networkManager.OnTestURL += (cmd, url) =>
        {
            Debug.Log($"Network command received: {cmd}");
            settingsURLToTestInputField.text = url;
            radioStations[radioStations.Count - 1].url = url;
            SelectStation(radioStations.Count - 1);
        };

        networkManager.OnStationSelected += (cmd, stationIndex) =>
        {
            Debug.Log($"Network command received: {cmd}");
            SelectStation(stationIndex);
        };
        
        networkManager.OnMuteRequested += () =>
        {
            Debug.Log("Network command received: MUTE");
            if (!radioStreamer.IsMuted())
            {
                radioStreamer.ToggleMuteStream();
            }
        };
        
        networkManager.OnUnmuteRequested += () =>
        {
            Debug.Log("Network command received: UNMUTE");
            if (radioStreamer.IsMuted())
            {
                radioStreamer.ToggleMuteStream();
            }
        };
        
        networkManager.OnStateRequested += () =>
        {
            // Return current state as: STATION_INDEX:MUTE_STATE
            string muteState = radioStreamer.IsMuted() ? "MUTED" : "PLAYING";
            string state = $"STATE|{currentStationIndex}|{muteState}";
            Debug.Log($"State requested, returning: {state}");
            return state;
        };
    }
    
    async void PollPlayerState()
    {
        string playerIP = Settings.GetPlayerIPAddress();
        if (string.IsNullOrEmpty(playerIP))
            return;
        
        string response = await networkManager.SendCommand(playerIP, "GET_STATE");
        
        if (response.StartsWith("STATE|"))
        {
            ParseAndApplyState(response);
        }
        else
        {
            Debug.LogWarning($"Unexpected state response: {response}");
        }
    }
    
    void ParseAndApplyState(string stateResponse)
    {
        // Expected format: STATE|stationIndex|muteState
        string[] parts = stateResponse.Split('|');
        if (parts.Length != 3)
        {
            Debug.LogError($"Invalid state format: {stateResponse}");
            return;
        }
        
        if (int.TryParse(parts[1], out int stationIndex))
        {
            // Update current station index and UI
            if (stationIndex >= 0 && stationIndex < radioStations.Count)
            {
                currentStationIndex = stationIndex;
                stationNameText.text = radioStations[currentStationIndex].name;
                UpdateScreensaverStationImage();
            }
        }
        
        // Update mute button state
        bool isMuted = parts[2] == "MUTED";
        UpdateMuteButton(isMuted);
    }
    
    async void SendCommandToPlayer(string command)
    {
        string playerIP = Settings.GetPlayerIPAddress();
        if (string.IsNullOrEmpty(playerIP))
        {
            Debug.LogWarning("No player IP configured");
            return;
        }
        
        string response = await networkManager.SendCommand(playerIP, command);
        
        if (!response.StartsWith("OK"))
        {
            Debug.LogWarning($"Command failed: {command} -> {response}");
        }
    }

    void UpdateLayoutForOrientation()
    {
        bool isLandscape = Screen.width > Screen.height;
        GridLayoutGroup grid = stationListParent.GetComponent<GridLayoutGroup>();
        
        if (isLandscape)
        {
            canvasScaler.matchWidthOrHeight = 0.6f;
            stationNameText.rectTransform.offsetMin = new Vector2(320f, 860f);
            stationNameText.rectTransform.offsetMax = new Vector2(-150f, -60f);
            stationScrollView.offsetMax = new Vector2(-150f, -280f);
            grid.constraintCount = 3;
        }
        else // portrait
        {

            /*
            stationNameText.rectTransform.offsetMin = new Vector2(150f, 1200f);
            stationNameText.rectTransform.offsetMax = new Vector2(-150f, -220f);
            stationScrollView.offsetMax = new Vector2(-150f, -720f);
            */

            canvasScaler.matchWidthOrHeight = 0.0f;
            float screenHeight = Screen.height;
            
            // Fixed margins
            float fixedTopMargin = 220f;
            float fixedBottomMargin = 150f;
            
            // Flexible space to distribute
            float flexibleSpace = screenHeight - fixedTopMargin - fixedBottomMargin;
            
            // Proportional distribution (500:1050 ratio)
            float nameHeightRatio = 500f / 1550f;
            float scrollHeightRatio = 1050f / 1550f;
            
            // Calculate heights
            float nameHeight = flexibleSpace * nameHeightRatio;
            float scrollHeight = flexibleSpace * scrollHeightRatio;
            Debug.Log($"nameHeight: {nameHeight}, scrollHeight: {scrollHeight}");
            
            // stationNameText offsets
            float nameBottom = screenHeight - fixedTopMargin - nameHeight;
            stationNameText.rectTransform.offsetMin = new Vector2(150f, nameBottom);
            stationNameText.rectTransform.offsetMax = new Vector2(-150f, -fixedTopMargin);
            
            // stationScrollView offsets
            float scrollTop = fixedTopMargin + nameHeight;
            stationScrollView.offsetMax = new Vector2(-150f, -scrollTop);
            
            float cellHeight = grid.cellSize.y;
            float spacingHeight = grid.spacing.y;
            int rows = Mathf.FloorToInt(scrollHeight / (cellHeight + spacingHeight));
            grid.constraintCount = rows;
        }
        EnsureContentWidthForScrolling();
    }

    void EnsureContentWidthForScrolling()
    {
        RectTransform contentRect = stationListParent.GetComponent<RectTransform>();
        GridLayoutGroup gridLayout = contentRect.GetComponent<GridLayoutGroup>();

        Canvas.ForceUpdateCanvases();
        LayoutRebuilder.ForceRebuildLayoutImmediate(contentRect);

        int rows = gridLayout.constraintCount;
        int columns = Mathf.CeilToInt(radioStations.Count / (float)rows);

        float cellWidth = gridLayout.cellSize.x;
        float spacing = gridLayout.spacing.x;

        float totalWidth = (columns * cellWidth) + ((columns - 1) * spacing);

        contentRect.SetSizeWithCurrentAnchors(RectTransform.Axis.Horizontal, totalWidth);
    }
    
}
