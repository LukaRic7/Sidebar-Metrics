using LibreHardwareMonitor.Hardware;

namespace HardwareMonitor.Core.Sensors;

public sealed class SensorManager
{
    private readonly object _gate = new();
    private readonly SensorCache _cache;
    private readonly Dictionary<string, ISensor> _sensors = new(StringComparer.Ordinal);
    private readonly Dictionary<string, SensorInfo> _metadata = new(StringComparer.Ordinal);
    private readonly HashSet<string> _activeIds = new(StringComparer.Ordinal);

    public SensorManager(SensorCache cache)
    {
        _cache = cache;
    }

    public IReadOnlySet<string> ActiveIds
    {
        get { lock (_gate) return new HashSet<string>(_activeIds, StringComparer.Ordinal); }
    }

    public IReadOnlyDictionary<string, SensorInfo> Metadata
    {
        get { lock (_gate) return new Dictionary<string, SensorInfo>(_metadata, StringComparer.Ordinal); }
    }

    public int SensorCount { get { lock (_gate) return _metadata.Count; } }
    public int ActiveCount { get { lock (_gate) return _activeIds.Count; } }

    public void RestoreSelection(IEnumerable<string> ids)
    {
        lock (_gate)
        {
            _activeIds.Clear();
            foreach (string id in ids)
                if (_metadata.ContainsKey(id))
                    _activeIds.Add(id);
            _cache.MarkActiveSelection(_activeIds);
        }
    }

    public (bool Success, IReadOnlyList<string>? UnknownIds) SetSelection(IEnumerable<string> ids)
    {
        lock (_gate)
        {
            var selected = new HashSet<string>(StringComparer.Ordinal);
            var unknown = new List<string>();
            foreach (string id in ids)
            {
                if (_metadata.ContainsKey(id))
                    selected.Add(id);
                else
                    unknown.Add(id);
            }
            if (unknown.Count != 0)
                return (false, unknown);
            _activeIds.Clear();
            foreach (string id in selected) _activeIds.Add(id);
            _cache.MarkActiveSelection(_activeIds);
            return (true, null);
        }
    }

    public bool Enable(IEnumerable<string> ids, out IReadOnlyList<string> unknown)
    {
        lock (_gate)
        {
            var unknownList = new List<string>();
            foreach (string id in ids)
            {
                if (_metadata.ContainsKey(id)) _activeIds.Add(id);
                else unknownList.Add(id);
            }
            unknown = unknownList;
            _cache.MarkActiveSelection(_activeIds);
            return unknownList.Count == 0;
        }
    }

    public bool Disable(IEnumerable<string> ids, out IReadOnlyList<string> unknown)
    {
        lock (_gate)
        {
            var unknownList = new List<string>();
            foreach (string id in ids)
            {
                if (_metadata.ContainsKey(id)) _activeIds.Remove(id);
                else unknownList.Add(id);
            }
            unknown = unknownList;
            _cache.MarkActiveSelection(_activeIds);
            return unknownList.Count == 0;
        }
    }

    public void Discover(IEnumerable<IHardware> hardwareTree)
    {
        var newSensors = new Dictionary<string, ISensor>(StringComparer.Ordinal);
        var newMetadata = new Dictionary<string, SensorInfo>(StringComparer.Ordinal);

        foreach (IHardware hardware in hardwareTree)
            DiscoverHardware(hardware, newSensors, newMetadata);

        lock (_gate)
        {
            foreach (string id in _metadata.Keys)
                if (!newMetadata.ContainsKey(id))
                    _cache.Remove(id);

            _sensors.Clear();
            _metadata.Clear();
            foreach ((string id, ISensor sensor) in newSensors)
            {
                _sensors.Add(id, sensor);
                _metadata.Add(id, newMetadata[id]);
            }

            var retained = new HashSet<string>(StringComparer.Ordinal);
            foreach (string id in _activeIds)
                if (_metadata.ContainsKey(id))
                    retained.Add(id);
            _activeIds.Clear();
            foreach (string id in retained) _activeIds.Add(id);
        }
    }

    private static void DiscoverHardware(
        IHardware hardware,
        Dictionary<string, ISensor> sensors,
        Dictionary<string, SensorInfo> metadata)
    {
        foreach (ISensor sensor in hardware.Sensors)
        {
            string id = sensor.Identifier.ToString();
            sensors[id] = sensor;
            float? value = sensor.Value;
            double? safeValue = value is float f && float.IsFinite(f) ? f : null;
            metadata[id] = new SensorInfo(
                id,
                sensor.Name,
                sensor.SensorType.ToString(),
                hardware.Name,
                hardware.HardwareType.ToString(),
                hardware.Identifier.ToString(),
                id,
                false,
                safeValue is not null,
                safeValue,
                SafeFloat(sensor.Min),
                SafeFloat(sensor.Max));
        }

        foreach (IHardware child in hardware.SubHardware)
            DiscoverHardware(child, sensors, metadata);
    }

    public void UpdateActiveReadings()
    {
        DateTimeOffset timestamp = DateTimeOffset.UtcNow;
        lock (_gate)
        {
            foreach ((string id, ISensor sensor) in _sensors)
            {
                if (!_metadata.TryGetValue(id, out SensorInfo? info))
                    continue;

                float? raw = sensor.Value;
                bool available = raw is float f && float.IsFinite(f);
                double? value = available ? raw : null;
                double? min = SafeFloat(sensor.Min);
                double? max = SafeFloat(sensor.Max);
                bool active = _activeIds.Contains(id);
                _metadata[id] = info with
                {
                    IsActive = active,
                    IsAvailable = available,
                    Value = value,
                    Min = min,
                    Max = max
                };

                if (active)
                    _cache.Replace(id, new SensorReading(
                        id, sensor.Name, sensor.SensorType.ToString(), value,
                        min, max, timestamp, available, true));
                else
                    _cache.Remove(id);
            }
        }
    }

    public SensorInfo[] GetSensorSnapshot()
    {
        lock (_gate)
        {
            var result = new SensorInfo[_metadata.Count];
            int i = 0;
            foreach ((string id, SensorInfo info) in _metadata)
            {
                SensorReading? reading = _cache.Get(id);
                result[i++] = info with
                {
                    IsActive = _activeIds.Contains(id),
                    IsAvailable = reading?.IsAvailable ?? info.IsAvailable,
                    Value = reading?.Value ?? info.Value,
                    Min = reading?.Min ?? info.Min,
                    Max = reading?.Max ?? info.Max
                };
            }
            return result;
        }
    }

    private static double? SafeFloat(float? value)
    {
        return value is float f && float.IsFinite(f) ? f : null;
    }
}
