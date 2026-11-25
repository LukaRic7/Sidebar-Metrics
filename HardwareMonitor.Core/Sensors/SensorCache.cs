namespace HardwareMonitor.Core.Sensors;

public sealed class SensorCache
{
    private readonly object _gate = new();
    private readonly Dictionary<string, SensorReading> _readings = new(StringComparer.Ordinal);

    public void Replace(string id, SensorReading reading)
    {
        lock (_gate) _readings[id] = reading;
    }

    public void Remove(string id)
    {
        lock (_gate) _readings.Remove(id);
    }

    public SensorReading? Get(string id)
    {
        lock (_gate)
            return _readings.TryGetValue(id, out SensorReading? reading) ? reading : null;
    }

    public SensorReading[] GetAll(IEnumerable<string> ids)
    {
        var result = new List<SensorReading>();
        lock (_gate)
        {
            foreach (string id in ids)
                if (_readings.TryGetValue(id, out SensorReading? reading))
                    result.Add(reading);
        }
        return result.ToArray();
    }

    public SensorReading[] GetActive()
    {
        lock (_gate)
        {
            var result = new List<SensorReading>();
            foreach (SensorReading reading in _readings.Values)
                if (reading.IsActive)
                    result.Add(reading);
            return result.ToArray();
        }
    }

    public void MarkActiveSelection(IReadOnlySet<string> activeIds)
    {
        lock (_gate)
        {
            foreach (SensorReading reading in _readings.Values.ToArray())
            {
                if (_readings.TryGetValue(reading.Id, out SensorReading? current))
                    _readings[reading.Id] = current with { IsActive = activeIds.Contains(reading.Id) };
            }
        }
    }
}
