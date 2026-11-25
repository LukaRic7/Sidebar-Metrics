using LibreHardwareMonitor.Hardware;

namespace HardwareMonitor.Core.Hardware;

public sealed class HardwareManager : IDisposable
{
    private readonly object _gate = new();
    private readonly Computer _computer;
    private readonly UpdateVisitor _updateVisitor = new();
    private readonly Dictionary<string, HardwareInfo> _hardware = new(StringComparer.Ordinal);
    private readonly Sensors.SensorManager _sensorManager;
    private bool _disposed;

    public HardwareManager(Sensors.SensorManager sensorManager)
    {
        _sensorManager = sensorManager;
        _computer = new Computer
        {
            IsBatteryEnabled = true,
            IsControllerEnabled = true,
            IsCpuEnabled = true,
            IsGpuEnabled = true,
            IsPowerMonitorEnabled = true,
            IsMemoryEnabled = true,
            IsMotherboardEnabled = true,
            IsNetworkEnabled = true,
            IsPsuEnabled = true,
            IsStorageEnabled = true
        };
        lock (_gate)
        {
            _computer.HardwareAdded += OnHardwareAdded;
            _computer.HardwareRemoved += OnHardwareRemoved;
            _computer.Open();
            RefreshDiscoveryLocked();
        }
    }

    public int HardwareCount { get { lock (_gate) return _hardware.Count; } }

    public HardwareInfo[] GetHardwareSnapshot()
    {
        lock (_gate)
            return _hardware.Values.ToArray();
    }

    public void RefreshDiscovery()
    {
        lock (_gate)
        {
            ThrowIfDisposed();
            RefreshDiscoveryLocked();
        }
    }

    public void UpdateSensors()
    {
        lock (_gate)
        {
            ThrowIfDisposed();
            _computer.Accept(_updateVisitor);
            _sensorManager.UpdateActiveReadings();
        }
    }

    private void RefreshDiscoveryLocked()
    {
        _hardware.Clear();
        var roots = new List<IHardware>();
        foreach (IHardware hardware in _computer.Hardware)
        {
            roots.Add(hardware);
            AddHardwareRecursive(hardware);
        }
        _sensorManager.Discover(roots);
    }

    private void AddHardwareRecursive(IHardware hardware)
    {
        string id = hardware.Identifier.ToString();
        _hardware[id] = new HardwareInfo(
            hardware.Name,
            hardware.HardwareType.ToString(),
            id,
            hardware.Parent?.Identifier.ToString());

        foreach (IHardware child in hardware.SubHardware)
            AddHardwareRecursive(child);
    }

    private void OnHardwareAdded(IHardware hardware)
    {
        lock (_gate)
        {
            if (!_disposed)
                RefreshDiscoveryLocked();
        }
    }

    private void OnHardwareRemoved(IHardware hardware)
    {
        lock (_gate)
        {
            if (!_disposed)
                RefreshDiscoveryLocked();
        }
    }

    private void ThrowIfDisposed()
    {
        if (_disposed)
            throw new ObjectDisposedException(nameof(HardwareManager));
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed) return;
            _disposed = true;
            _computer.HardwareAdded -= OnHardwareAdded;
            _computer.HardwareRemoved -= OnHardwareRemoved;
            _computer.Close();
        }
    }
}
