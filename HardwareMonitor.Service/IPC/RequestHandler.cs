using System.Text.Json;
using HardwareMonitor.Core.Configuration;
using HardwareMonitor.Core.Hardware;
using HardwareMonitor.Core.Services;
using HardwareMonitor.Core.Sensors;
using HardwareMonitor.Service.Models;

namespace HardwareMonitor.Service.IPC;

public sealed class RequestHandler
{
    private readonly HardwareManager _hardware;
    private readonly SensorManager _sensors;
    private readonly SensorCache _cache;
    private readonly ConfigurationManager _configuration;
    private readonly PollingService _polling;
    private readonly DateTimeOffset _startedAt;
    private readonly Func<int> _connectedClients;
    private readonly Action<string>? _log;

    public event Action? ShutdownRequested;

    public RequestHandler(
        HardwareManager hardware,
        SensorManager sensors,
        SensorCache cache,
        ConfigurationManager configuration,
        PollingService polling,
        Func<int> connectedClients,
        Action<string>? log = null)
    {
        _hardware = hardware;
        _sensors = sensors;
        _cache = cache;
        _configuration = configuration;
        _polling = polling;
        _connectedClients = connectedClients;
        _startedAt = DateTimeOffset.UtcNow;
        _log = log;
    }

    public Response Handle(Request request)
    {
        string? requestId = request.RequestId;
        if (string.IsNullOrWhiteSpace(requestId))
            return Response.Fail(null, "INVALID_REQUEST", "requestId is required.");
        if (string.IsNullOrWhiteSpace(request.Command))
            return Response.Fail(requestId, "INVALID_REQUEST", "command is required.");

        try
        {
            return request.Command.ToLowerInvariant() switch
            {
                "get_hardware" => Response.Ok(requestId, _hardware.GetHardwareSnapshot()),
                "get_sensors" => Response.Ok(requestId, _sensors.GetSensorSnapshot()),
                "get_active_sensors" => Response.Ok(requestId, _sensors.ActiveIds),
                "set_active_sensors" => HandleSetSelection(requestId, request),
                "enable_sensors" => HandleEnable(requestId, request),
                "disable_sensors" => HandleDisable(requestId, request),
                "get_values" => HandleGetValues(requestId, request),
                "get_all_values" => Response.Ok(requestId, _cache.GetActive()),
                "refresh_hardware" => HandleRefresh(requestId),
                "set_poll_interval" => HandleSetInterval(requestId, request),
                "get_status" => HandleStatus(requestId),
                "shutdown" => HandleShutdown(requestId),
                _ => Response.Fail(requestId, "UNKNOWN_COMMAND", $"Unknown command: {request.Command}")
            };
        }
        catch (Exception ex)
        {
            _log?.Invoke("Request failure: " + ex.Message);
            return Response.Fail(requestId, "INTERNAL_ERROR", ex.Message);
        }
    }

    private Response HandleSetSelection(string requestId, Request request)
    {
        IReadOnlyList<string>? ids = ReadStringArray(request, "sensors");
        if (ids is null)
            return Response.Fail(requestId, "INVALID_ARGUMENT", "sensors must be a JSON string array.");

        (bool success, IReadOnlyList<string>? unknown) = _sensors.SetSelection(ids);
        if (!success)
            return Response.Fail(requestId, "UNKNOWN_SENSOR_IDS",
                "Unknown sensor IDs: " + string.Join(", ", unknown ?? Array.Empty<string>()));

        _configuration.Update(config =>
        {
            config.ActiveSensorIds.Clear();
            foreach (string id in _sensors.ActiveIds) config.ActiveSensorIds.Add(id);
        });
        _log?.Invoke($"Active sensor selection replaced ({ids.Count} requested).");
        return Response.Ok(requestId, _sensors.ActiveIds);
    }

    private Response HandleEnable(string requestId, Request request)
    {
        IReadOnlyList<string>? ids = ReadStringArray(request, "sensors");
        if (ids is null)
            return Response.Fail(requestId, "INVALID_ARGUMENT", "sensors must be a JSON string array.");

        bool success = _sensors.Enable(ids, out IReadOnlyList<string> unknown);
        if (!success)
            return Response.Fail(requestId, "UNKNOWN_SENSOR_IDS",
                "Unknown sensor IDs: " + string.Join(", ", unknown));

        PersistActiveSelection();
        return Response.Ok(requestId, _sensors.ActiveIds);
    }

    private Response HandleDisable(string requestId, Request request)
    {
        IReadOnlyList<string>? ids = ReadStringArray(request, "sensors");
        if (ids is null)
            return Response.Fail(requestId, "INVALID_ARGUMENT", "sensors must be a JSON string array.");

        bool success = _sensors.Disable(ids, out IReadOnlyList<string> unknown);
        if (!success)
            return Response.Fail(requestId, "UNKNOWN_SENSOR_IDS",
                "Unknown sensor IDs: " + string.Join(", ", unknown));

        PersistActiveSelection();
        return Response.Ok(requestId, _sensors.ActiveIds);
    }

    private void PersistActiveSelection()
    {
        _configuration.Update(config =>
        {
            config.ActiveSensorIds.Clear();
            foreach (string id in _sensors.ActiveIds) config.ActiveSensorIds.Add(id);
        });
        _log?.Invoke("Active sensor selection changed.");
    }

    private Response HandleGetValues(string requestId, Request request)
    {
        IReadOnlyList<string>? ids = ReadStringArray(request, "sensors");
        if (ids is null)
            return Response.Fail(requestId, "INVALID_ARGUMENT", "sensors must be a JSON string array.");

        var result = new object[ids.Count];
        IReadOnlySet<string> active = _sensors.ActiveIds;
        for (int i = 0; i < ids.Count; i++)
        {
            string id = ids[i];
            SensorReading? reading = _cache.Get(id);
            result[i] = new
            {
                id,
                isActive = active.Contains(id),
                reading
            };
        }
        return Response.Ok(requestId, result);
    }

    private Response HandleRefresh(string requestId)
    {
        _hardware.RefreshDiscovery();
        return Response.Ok(requestId, new
        {
            hardwareCount = _hardware.HardwareCount,
            sensorCount = _sensors.SensorCount
        });
    }

    private Response HandleSetInterval(string requestId, Request request)
    {
        if (request.Arguments is null ||
            !request.Arguments.TryGetValue("intervalMs", out JsonElement value) &&
            !request.Arguments.TryGetValue("interval", out value))
            return Response.Fail(requestId, "INVALID_ARGUMENT", "intervalMs is required.");

        if (!value.TryGetInt32(out int milliseconds))
            return Response.Fail(requestId, "INVALID_ARGUMENT", "intervalMs must be an integer.");

        try
        {
            _polling.SetPollingInterval(milliseconds);
            return Response.Ok(requestId, new { pollingIntervalMs = _polling.PollingInterval });
        }
        catch (ArgumentOutOfRangeException)
        {
            return Response.Fail(requestId, "INVALID_ARGUMENT",
                $"intervalMs must be between {HardwareConfiguration.MinimumPollingIntervalMilliseconds} and {HardwareConfiguration.MaximumPollingIntervalMilliseconds}.");
        }
    }

    private Response HandleStatus(string requestId)
    {
        return Response.Ok(requestId, new
        {
            uptimeSeconds = Math.Max(0, (DateTimeOffset.UtcNow - _startedAt).TotalSeconds),
            pollingIntervalMs = _polling.PollingInterval,
            lastSuccessfulHardwareUpdate = _polling.LastSuccessfulUpdate,
            hardwareCount = _hardware.HardwareCount,
            sensorCount = _sensors.SensorCount,
            activeSensorCount = _sensors.ActiveCount,
            connectedClients = _connectedClients(),
            pollingState = _polling.IsRunning ? "running" : "stopped",
            recentPollingErrors = _polling.LastError is null
                ? Array.Empty<string>()
                : new[] { _polling.LastError }
        });
    }

    private Response HandleShutdown(string requestId)
    {
        Response response = Response.Ok(requestId, new { shutdown = true });
        ShutdownRequested?.Invoke();
        return response;
    }

    private static IReadOnlyList<string>? ReadStringArray(Request request, string key)
    {
        if (request.Arguments is null ||
            !request.Arguments.TryGetValue(key, out JsonElement element) ||
            element.ValueKind != JsonValueKind.Array)
            return null;

        var values = new List<string>();
        foreach (JsonElement item in element.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.String)
                return null;
            string? value = item.GetString();
            if (string.IsNullOrWhiteSpace(value))
                return null;
            values.Add(value);
        }
        return values;
    }
}
