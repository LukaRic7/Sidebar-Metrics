using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using HardwareMonitor.Service.Models;

namespace HardwareMonitor.Service.IPC;

public sealed class PipeServer : IAsyncDisposable
{
    public const string PipeName = "HardwareMonitorPipe";

    private readonly RequestHandler _handler;
    private readonly Action<string>? _log;
    private readonly CancellationTokenSource _cts = new();
    private readonly SemaphoreSlim _clientSlots = new(32, 32);
    private readonly HashSet<Task> _clientTasks = new();
    private readonly object _tasksGate = new();
    private RequestQueue? _queue;
    private int _connectedClients;
    private Task? _acceptLoop;

    public PipeServer(RequestHandler handler, Action<string>? log = null)
    {
        _handler = handler;
        _log = log;
    }

    public int ConnectedClients
    {
        get { return Volatile.Read(ref _connectedClients); }
    }

    public Task StartAsync()
    {
        NamedPipeServerStream firstPipe = CreatePipe();
        _queue = new RequestQueue(256, 4, ProcessQueuedRequestAsync);
        _acceptLoop = AcceptLoopAsync(firstPipe, _cts.Token);
        _log?.Invoke($"Named pipe '{PipeName}' listening.");
        return Task.CompletedTask;
    }

    private async Task AcceptLoopAsync(
        NamedPipeServerStream firstPipe,
        CancellationToken cancellationToken)
    {
        NamedPipeServerStream? pendingPipe = firstPipe;
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                await _clientSlots.WaitAsync(cancellationToken).ConfigureAwait(false);
                NamedPipeServerStream pipe;
                if (pendingPipe is not null)
                {
                    pipe = pendingPipe;
                    pendingPipe = null;
                }
                else
                {
                    try
                    {
                        pipe = CreatePipe();
                    }
                    catch (Exception ex)
                    {
                        _clientSlots.Release();
                        _log?.Invoke("Named pipe listener creation failed: " + ex);
                        await Task.Delay(1000, cancellationToken).ConfigureAwait(false);
                        continue;
                    }
                }

                Task clientTask = HandleClientAsync(pipe, cancellationToken);

                lock (_tasksGate)
                {
                    _clientTasks.Add(clientTask);
                    _ = clientTask.ContinueWith(
                        task => { lock (_tasksGate) _clientTasks.Remove(task); },
                        CancellationToken.None,
                        TaskContinuationOptions.ExecuteSynchronously,
                        TaskScheduler.Default);
                }
            }

        }
        catch (OperationCanceledException) { }
        catch (Exception ex)
        {
            _log?.Invoke("Named pipe accept loop failed: " + ex);
        }
        finally
        {
            if (pendingPipe is not null)
                await pendingPipe.DisposeAsync().ConfigureAwait(false);
        }
    }

    private async Task HandleClientAsync(
        NamedPipeServerStream pipe,
        CancellationToken cancellationToken)
    {
        try
        {
            Interlocked.Increment(ref _connectedClients);
            _log?.Invoke("Named pipe client connected.");
            var handler = new PipeClientHandler(pipe, _queue!, _log);
            await handler.RunAsync(cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            Interlocked.Decrement(ref _connectedClients);
            _clientSlots.Release();
            _log?.Invoke("Named pipe client disconnected.");
        }
    }

    private Task ProcessQueuedRequestAsync(
        QueuedRequest queued,
        CancellationToken cancellationToken)
    {
        try
        {
            Request? request = JsonSerializer.Deserialize<Request>(
                queued.Payload,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

            Response response;
            if (request is null)
                response = Response.Fail(null, "MALFORMED_REQUEST", "JSON payload is null.");
            else
                response = _handler.Handle(request);

            queued.TrySetResult(response);
        }
        catch (JsonException ex)
        {
            queued.TrySetResult(Response.Fail(
                null,
                "MALFORMED_REQUEST",
                "Malformed JSON: " + ex.Message));
        }
        catch (Exception ex)
        {
            queued.TrySetException(ex);
        }
        return Task.CompletedTask;
    }

    private static NamedPipeServerStream CreatePipe()
    {
        PipeSecurity security = new();
        SecurityIdentifier system = new(WellKnownSidType.LocalSystemSid, null);
        SecurityIdentifier admins = new(WellKnownSidType.BuiltinAdministratorsSid, null);
        using WindowsIdentity identity = WindowsIdentity.GetCurrent();
        SecurityIdentifier user = identity.User ?? throw new InvalidOperationException("No current user SID.");

        security.AddAccessRule(new PipeAccessRule(
            system, PipeAccessRights.FullControl, AccessControlType.Allow));
        security.AddAccessRule(new PipeAccessRule(
            admins, PipeAccessRights.FullControl, AccessControlType.Allow));
        security.AddAccessRule(new PipeAccessRule(
            user, PipeAccessRights.ReadWrite | PipeAccessRights.Synchronize,
            AccessControlType.Allow));

        return NamedPipeServerStreamAcl.Create(
            PipeName,
            PipeDirection.InOut,
            32,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous,
            64 * 1024,
            4 * 1024 * 1024,
            security,
            HandleInheritability.None,
            (PipeAccessRights)0);
    }

    public async ValueTask DisposeAsync()
    {
        _cts.Cancel();
        if (_acceptLoop is not null)
        {
            try { await _acceptLoop.ConfigureAwait(false); }
            catch (OperationCanceledException) { }
        }

        Task[] tasks;
        lock (_tasksGate) tasks = _clientTasks.ToArray();
        if (tasks.Length != 0)
        {
            try { await Task.WhenAll(tasks).ConfigureAwait(false); }
            catch { }
        }
        if (_queue is not null) await _queue.DisposeAsync().ConfigureAwait(false);
        _clientSlots.Dispose();
        _cts.Dispose();
    }
}
