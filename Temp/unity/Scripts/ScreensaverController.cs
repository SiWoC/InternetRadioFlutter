using UnityEngine;
using UnityEngine.UI;
using UnityEngine.InputSystem;
using System.Collections;

public class ScreensaverController : MonoBehaviour
{

    public Button screensaverButton; // Full-screen button for touch detection
    public Image stationImage; // Bouncing station image (child of button)
    public Sprite unknown;
    public GameObject settingsPanel;

    private float inactivityTimeout = 60f; // seconds before screensaver activates
    private float bounceSpeed = 200f;

    private bool isScreensaverActive = false;
    private float lastInputTime;
    private Vector2 currentVelocity;
    private RectTransform stationImageRect;
    private RectTransform screensaverButtonRect;
    private Vector2 screenBounds;
    private int currentWidth;
    private int currentHeight;
    
    void Start()
    {
        lastInputTime = Time.time;
        screensaverButtonRect = screensaverButton.GetComponent<RectTransform>();
        screensaverButton.gameObject.SetActive(false); // Start hidden
        stationImageRect = stationImage.GetComponent<RectTransform>();
        
        currentWidth = Screen.width;
        currentHeight = Screen.height;
        UpdateScreenBounds();
    }

    void Update()
    {
        // Check for screen dimension changes
        if (Screen.width != currentWidth || Screen.height != currentHeight)
        {
            currentWidth = Screen.width;
            currentHeight = Screen.height;
            UpdateScreenBounds();
        }
        
        // Check if screensaver should activate
        if (!isScreensaverActive && Time.time - lastInputTime > inactivityTimeout && !settingsPanel.activeSelf)
        {
            EnterScreensaver();
        }
        
        // Update bouncing animation
        if (isScreensaverActive)
        {
            UpdateBouncingAnimation();
        }
    }
    
    public void OnScreensaverTouched()
    {
        lastInputTime = Time.time;
        isScreensaverActive = false;
        screensaverButton.gameObject.SetActive(false);
    }
    
    public void ResetTimer()
    {
        lastInputTime = Time.time;
        Debug.Log("Screensaver timer reset");
    }
    
    public bool IsScreensaverActive()
    {
        return isScreensaverActive;
    }

    void EnterScreensaver()
    {
        isScreensaverActive = true;
        screensaverButton.gameObject.SetActive(true);
        // Set random initial position and velocity
        SetRandomPositionAndVelocity();
        
    }
    
    void SetRandomPositionAndVelocity()
    {
        // Random position within bounds
        Vector2 randomPos = new Vector2(
            Random.Range(-screenBounds.x, screenBounds.x),
            Random.Range(-screenBounds.y, screenBounds.y)
        );
        stationImageRect.anchoredPosition = randomPos;
        
        // Random velocity
        currentVelocity = new Vector2(
            Random.Range(-bounceSpeed, bounceSpeed),
            Random.Range(-bounceSpeed, bounceSpeed)
        );
    }
    
    void UpdateBouncingAnimation()
    {
        if (stationImageRect == null) return;
        
        // Update position
        Vector2 newPosition = stationImageRect.anchoredPosition + currentVelocity * Time.deltaTime;
        
        // Bounce off edges
        // Hitting East wall
        if (newPosition.x > screenBounds.x)
        {
            float currentSpeed = currentVelocity.magnitude;
            float randomAngle;
            bool goingNorth = (currentVelocity.y > 0);
            if (goingNorth) // North East
            {
                // continue North West
                randomAngle = Random.Range(90f, 180f) * Mathf.Deg2Rad;
            }
            else // South East
            {
                // continue South West
                randomAngle = Random.Range(180f, 270f) * Mathf.Deg2Rad;
            }

            currentVelocity = new Vector2(
                Mathf.Cos(randomAngle) * currentSpeed,
                Mathf.Sin(randomAngle) * currentSpeed
            );
            newPosition.x = Mathf.Clamp(newPosition.x, -screenBounds.x, screenBounds.x);
        }
        
        // Hitting West wall
        if (newPosition.x < -screenBounds.x)
        {
            float currentSpeed = currentVelocity.magnitude;
            float randomAngle;
            bool goingNorth = (currentVelocity.y > 0);
            if (goingNorth) // North West
            {
                // continue North East
                randomAngle = Random.Range(0f, 90f) * Mathf.Deg2Rad;
            }
            else // South West
            {
                // continue South East
                randomAngle = Random.Range(270f, 360f) * Mathf.Deg2Rad;
            }

            currentVelocity = new Vector2(
                Mathf.Cos(randomAngle) * currentSpeed,
                Mathf.Sin(randomAngle) * currentSpeed
            );
            newPosition.x = Mathf.Clamp(newPosition.x, -screenBounds.x, screenBounds.x);
        }
        
        // Hitting North wall
        if (newPosition.y > screenBounds.y)
        {
            float currentSpeed = currentVelocity.magnitude;
            float randomAngle;
            bool goingEast = (currentVelocity.x > 0);
            if (goingEast) // North East
            {
                // continue South East
                randomAngle = Random.Range(270f, 360f) * Mathf.Deg2Rad;
            }
            else // North West
            {
                // continue South West
                randomAngle = Random.Range(180f, 270f) * Mathf.Deg2Rad;
            }

            currentVelocity = new Vector2(
                Mathf.Cos(randomAngle) * currentSpeed,
                Mathf.Sin(randomAngle) * currentSpeed
            );
            newPosition.y = Mathf.Clamp(newPosition.y, -screenBounds.y, screenBounds.y);
        }
        
        // Hitting South wall
        if (newPosition.y < -screenBounds.y)
        {
            float currentSpeed = currentVelocity.magnitude;
            float randomAngle;
            bool goingEast = (currentVelocity.x > 0);
            if (goingEast) // South East
            {
                // continue North East
                randomAngle = Random.Range(0f, 90f) * Mathf.Deg2Rad;
            }
            else // South West
            {
                // continue North West
                randomAngle = Random.Range(90f, 180f) * Mathf.Deg2Rad;
            }

            currentVelocity = new Vector2(
                Mathf.Cos(randomAngle) * currentSpeed,
                Mathf.Sin(randomAngle) * currentSpeed
            );
            newPosition.y = Mathf.Clamp(newPosition.y, -screenBounds.y, screenBounds.y);
        }
        
        // Apply new position
        stationImageRect.anchoredPosition = newPosition;
    }
    
    public void SetStationImage(Sprite stationSprite)
    {
        if (stationSprite != null)
        {
            stationImage.sprite = stationSprite;
        }
        else
        {
            // TODO create default image
            stationImage.sprite = unknown;
        }
    }
    
    void UpdateScreenBounds()
    {
        screenBounds = new Vector2(
            screensaverButtonRect.rect.width * 0.5f - stationImageRect.rect.width * 0.5f,
            screensaverButtonRect.rect.height * 0.5f - stationImageRect.rect.height * 0.5f
        );
    }
    
}
