using System.Security.Principal;
using HardwareMonitor.Core.Configuration;
using HardwareMonitor.Core.Hardware;
using HardwareMonitor.Core.Services;
using HardwareMonitor.Core.Sensors;
using HardwareMonitor.Service.IPC;
using HardwareMonitor.Service.Logging;

internal static class Program
{
    private static async Task<int> Main(string[] args)
    {
        using var logger = new BoundedLogger();
        if (!IsAdministrator())
        {
            const string message = "Administrator privileges are required to run HardwareMonitor.Service.";
            Console.Error.WriteLine(message);
            logger.Error(message);
            return 2;
        }

        using var instanceMutex = new Mutex(
            initiallyOwned: true,
            name: @"Local\HardwareMonitor.Service",
            createdNew: out bool createdNew);
        if (!createdNew)
        {
            const string message = "HardwareMonitor.Service is already running in this session.";
            logger.Info(message);
            Console.Error.WriteLine(message);
            return 3;
        }

        logger.Info("HardwareMonitor daemon starting.");
        var shutdown = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        ConsoleCancelEventHandler cancelHandler = (sender, eventArgs) =>
        {
            eventArgs.Cancel = true;
            logger.Info("Ctrl+C received.");
            shutdown.TrySetResult();
        };
        Console.CancelKeyPress += cancelHandler;

        HardwareManager? hardware = null;
        PollingService? polling = null;
        PipeServer? pipeServer = null;
        try
        {
            var configuration = new ConfigurationManager();
            HardwareConfiguration config = configuration.Snapshot();

            var cache = new SensorCache();
            var sensors = new SensorManager(cache);
            hardware = new HardwareManager(sensors);
            sensors.RestoreSelection(config.ActiveSensorIds);

            polling = new PollingService(hardware, configuration, logger.Error, logger.Info);
            var handler = new RequestHandler(
                hardware,
                sensors,
                cache,
                configuration,
                polling,
                () => pipeServer?.ConnectedClients ?? 0,
                logger.Error);

            pipeServer = new PipeServer(handler, logger.Info);
            handler.ShutdownRequested += () =>
            {
                logger.Info("Shutdown requested by a pipe client.");
                shutdown.TrySetResult();
            };

            await polling.StartAsync();
            await pipeServer.StartAsync();
            logger.Info(
                $"Hardware discovery complete: {hardware.HardwareCount} hardware components, " +
                $"{sensors.SensorCount} sensors, {sensors.ActiveCount} active.");

            await shutdown.Task;
            logger.Info("HardwareMonitor daemon shutting down.");
            return 0;
        }
        catch (Exception ex)
        {
            logger.Error("Startup or runtime failure: " + ex);
            Console.Error.WriteLine("HardwareMonitor failed: " + ex.Message);
            return 1;
        }
        finally
        {
            Console.CancelKeyPress -= cancelHandler;
            if (pipeServer is not null) await pipeServer.DisposeAsync();
            if (polling is not null) await polling.DisposeAsync();
            hardware?.Dispose();
            logger.Info("HardwareMonitor daemon stopped.");
        }
    }

    private static bool IsAdministrator()
    {
        using WindowsIdentity identity = WindowsIdentity.GetCurrent();
        var principal = new WindowsPrincipal(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }
}
