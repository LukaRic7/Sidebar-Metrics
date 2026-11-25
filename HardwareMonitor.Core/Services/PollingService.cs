using HardwareMonitor.Core.Configuration;
using HardwareMonitor.Core.Hardware;

namespace HardwareMonitor.Core.Services;

public sealed class PollingService : IAsyncDisposable
{
    private readonly object _gate = new();
    private readonly HardwareManager _hardware;
    private readonly ConfigurationManager _configuration;
    private readonly Action<string>? _logError;
    private readonly Action<string>? _logInfo;
    private CancellationTokenSource? _cts;
    private Task? _loop;
    private int _interval;
    private bool _running;
    private DateTimeOffset? _lastSuccessfulUpdate;
    private string? _lastError;

    public PollingService(
        HardwareManager hardware,
        ConfigurationManager configuration,
        Action<string>? logError = null,
        Action<string>? logInfo = null)
    {
        _hardware = hardware;
        _configuration = configuration;
        _logError = logError;
        _logInfo = logInfo;
        _interval = _configuration.Snapshot().PollingIntervalMilliseconds;
    }

    public int PollingInterval
    {
        get { lock (_gate) return _interval; }
    }

    public bool IsRunning
    {
        get { lock (_gate) return _running; }
    }

    public DateTimeOffset? LastSuccessfulUpdate
    {
        get { lock (_gate) return _lastSuccessfulUpdate; }
    }

    public string? LastError
    {
        get { lock (_gate) return _lastError; }
    }

    public void SetPollingInterval(int milliseconds)
    {
        if (milliseconds < HardwareConfiguration.MinimumPollingIntervalMilliseconds ||
            milliseconds > HardwareConfiguration.MaximumPollingIntervalMilliseconds)
            throw new ArgumentOutOfRangeException(nameof(milliseconds));

        lock (_gate)
        {
            _interval = milliseconds;
            _configuration.Update(config => config.PollingIntervalMilliseconds = milliseconds);
            _logInfo?.Invoke($"Polling interval changed to {milliseconds} ms.");
        }
    }

    public Task StartAsync()
    {
        lock (_gate)
        {
            if (_loop is not null) return _loop;
            _cts = new CancellationTokenSource();
            _running = true;
            _loop = Task.Run(() => PollLoopAsync(_cts.Token));
        }
        return Task.CompletedTask;
    }

    private async Task PollLoopAsync(CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                try
                {
                    _hardware.UpdateSensors();
                    lock (_gate)
                    {
                        _lastSuccessfulUpdate = DateTimeOffset.UtcNow;
                        _lastError = null;
                    }
                }
                catch (Exception ex)
                {
                    lock (_gate) _lastError = ex.Message;
                    _logError?.Invoke("Polling failure: " + ex.Message);
                }

                int delay;
                lock (_gate) delay = _interval;
                await Task.Delay(delay, cancellationToken).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) { }
        finally
        {
            lock (_gate) _running = false;
        }
    }

    public async Task StopAsync()
    {
        Task? loop;
        CancellationTokenSource? cts;
        lock (_gate)
        {
            cts = _cts;
            loop = _loop;
            _cts = null;
            _loop = null;
        }
        if (cts is not null)
        {
            cts.Cancel();
            if (loop is not null)
            {
                try { await loop.ConfigureAwait(false); }
                catch (OperationCanceledException) { }
            }
            cts.Dispose();
        }
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync().ConfigureAwait(false);
    }
}
