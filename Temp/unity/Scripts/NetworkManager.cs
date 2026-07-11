using System;
using System.Collections.Concurrent;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using UnityEngine;

public class NetworkManager : MonoBehaviour
{
    private const int PORT = 6435;
    private const float CONNECTION_TIMEOUT = 2f; // seconds
    
    private TcpListener listener;
    private CancellationTokenSource listenerCancellation;
    private bool isListening = false;
    
    // Queue for commands that need to be executed on the Unity main thread
    private ConcurrentQueue<Action> mainThreadActions = new ConcurrentQueue<Action>();
    
    // Callback for when commands are received
    public event Action<string, int> OnStationSelected;
    public event Action<string, string> OnTestURL;
    public event Action OnMuteRequested;
    public event Action OnUnmuteRequested;
    public event Func<string> OnStateRequested;
    
    void OnDestroy()
    {
        StopListener();
    }
    
    void Update()
    {
        // Execute queued actions on main thread
        while (mainThreadActions.TryDequeue(out Action action))
        {
            try
            {
                action?.Invoke();
            }
            catch (Exception e)
            {
                Debug.LogError($"Error executing main thread action: {e.Message}");
            }
        }
    }
    
    #region Player Mode - Listener
    
    public void StartListener()
    {
        if (isListening)
        {
            Debug.LogWarning("Listener already running");
            return;
        }
        
        try
        {
            listener = new TcpListener(IPAddress.Any, PORT);
            listener.Start();
            isListening = true;
            listenerCancellation = new CancellationTokenSource();
            
            Debug.Log($"TCP Listener started on port {PORT}");
            
            // Start accepting connections on background thread
            Task.Run(() => AcceptClientsAsync(listenerCancellation.Token));
        }
        catch (Exception e)
        {
            Debug.LogError($"Failed to start listener: {e.Message}");
        }
    }
    
    public void StopListener()
    {
        if (!isListening)
            return;
        
        isListening = false;
        listenerCancellation?.Cancel();
        
        try
        {
            listener?.Stop();
            Debug.Log("TCP Listener stopped");
        }
        catch (Exception e)
        {
            Debug.LogError($"Error stopping listener: {e.Message}");
        }
    }
    
    private async Task AcceptClientsAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested && isListening)
        {
            try
            {
                TcpClient client = await listener.AcceptTcpClientAsync();
                Debug.Log($"Client connected from {client.Client.RemoteEndPoint}");
                
                // Handle client in separate task
                _ = Task.Run(() => HandleClientAsync(client, cancellationToken));
            }
            catch (Exception e)
            {
                if (!cancellationToken.IsCancellationRequested)
                {
                    Debug.LogError($"Error accepting client: {e.Message}");
                }
            }
        }
    }
    
    private async Task HandleClientAsync(TcpClient client, CancellationToken cancellationToken)
    {
        try
        {
            using (client)
            using (NetworkStream stream = client.GetStream())
            using (StreamReader reader = new StreamReader(stream, Encoding.UTF8))
            using (StreamWriter writer = new StreamWriter(stream, Encoding.UTF8) { AutoFlush = true })
            {
                while (!cancellationToken.IsCancellationRequested && client.Connected)
                {
                    string command = await reader.ReadLineAsync();
                    if (string.IsNullOrEmpty(command))
                        break;
                    
                    Debug.Log($"Received command: {command}");
                    string response = ProcessCommand(command);
                    
                    await writer.WriteLineAsync(response);
                }
            }
        }
        catch (Exception e)
        {
            Debug.LogError($"Error handling client: {e.Message}");
        }
    }
    
    private string ProcessCommand(string command)
    {
        try
        {
            if (command == "PING")
            {
                return "PONG";
            }
            else if (command.StartsWith("SELECT_STATION|"))
            {
                string[] parts = command.Split('|');
                if (parts.Length == 2 && int.TryParse(parts[1], out int stationIndex))
                {
                    // Queue action for main thread
                    mainThreadActions.Enqueue(() => OnStationSelected?.Invoke(command, stationIndex));
                    return "OK";
                }
                return "ERROR:Invalid station index";
            }
            else if (command.StartsWith("TESTURL|"))
            {
                string[] parts = command.Split('|');
                if (parts.Length == 2)
                {
                    // Queue action for main thread
                    mainThreadActions.Enqueue(() => OnTestURL?.Invoke(command, parts[1]));
                    return "OK";
                }
                return "ERROR:Invalid number of parts";
            }
            else if (command == "MUTE")
            {
                mainThreadActions.Enqueue(() => OnMuteRequested?.Invoke());
                return "OK";
            }
            else if (command == "UNMUTE")
            {
                mainThreadActions.Enqueue(() => OnUnmuteRequested?.Invoke());
                return "OK";
            }
            else if (command == "GET_STATE")
            {
                // Get state from callback (already on correct thread context)
                string state = OnStateRequested?.Invoke() ?? "ERROR:No state handler";
                return state;
            }
            else
            {
                return "ERROR:Unknown command";
            }
        }
        catch (Exception e)
        {
            return $"ERROR:{e.Message}";
        }
    }
    
    #endregion
    
    #region Remote Mode - Client
    
    public async Task<bool> TestConnection(string ipAddress)
    {
        try
        {
            using (TcpClient client = new TcpClient())
            {
                // Set connection timeout
                var connectTask = client.ConnectAsync(ipAddress, PORT);
                var timeoutTask = Task.Delay(TimeSpan.FromSeconds(CONNECTION_TIMEOUT));
                
                if (await Task.WhenAny(connectTask, timeoutTask) == timeoutTask)
                {
                    Debug.LogWarning($"Connection timeout to {ipAddress}:{PORT}");
                    return false;
                }
                
                if (!client.Connected)
                {
                    return false;
                }
                
                using (NetworkStream stream = client.GetStream())
                using (StreamReader reader = new StreamReader(stream, Encoding.UTF8))
                using (StreamWriter writer = new StreamWriter(stream, Encoding.UTF8) { AutoFlush = true })
                {
                    // Send PING
                    await writer.WriteLineAsync("PING");
                    
                    // Wait for PONG with timeout
                    var readTask = reader.ReadLineAsync();
                    var readTimeoutTask = Task.Delay(TimeSpan.FromSeconds(CONNECTION_TIMEOUT));
                    
                    if (await Task.WhenAny(readTask, readTimeoutTask) == readTimeoutTask)
                    {
                        Debug.LogWarning("PING response timeout");
                        return false;
                    }
                    
                    string response = await readTask;
                    Debug.Log("PING response: " + response);
                    bool success = response == "PONG";
                    
                    if (success)
                    {
                        Debug.Log($"Successfully connected to player at {ipAddress}");
                    }
                    else
                    {
                        Debug.LogWarning($"Unexpected response: {response}");
                    }
                    
                    return success;
                }
            }
        }
        catch (Exception e)
        {
            Debug.LogWarning($"Connection test failed: {e.Message}");
            return false;
        }
    }
    
    public async Task<string> SendCommand(string ipAddress, string command)
    {
        try
        {
            using (TcpClient client = new TcpClient())
            {
                var connectTask = client.ConnectAsync(ipAddress, PORT);
                var timeoutTask = Task.Delay(TimeSpan.FromSeconds(CONNECTION_TIMEOUT));
                
                if (await Task.WhenAny(connectTask, timeoutTask) == timeoutTask)
                {
                    return "ERROR:Connection timeout";
                }
                
                using (NetworkStream stream = client.GetStream())
                using (StreamReader reader = new StreamReader(stream, Encoding.UTF8))
                using (StreamWriter writer = new StreamWriter(stream, Encoding.UTF8) { AutoFlush = true })
                {
                    await writer.WriteLineAsync(command);
                    
                    var readTask = reader.ReadLineAsync();
                    var readTimeoutTask = Task.Delay(TimeSpan.FromSeconds(CONNECTION_TIMEOUT));
                    
                    if (await Task.WhenAny(readTask, readTimeoutTask) == readTimeoutTask)
                    {
                        return "ERROR:Response timeout";
                    }
                    
                    return await readTask;
                }
            }
        }
        catch (Exception e)
        {
            Debug.LogError($"Failed to send command: {e.Message}");
            return $"ERROR:{e.Message}";
        }
    }
    
    #endregion
}

