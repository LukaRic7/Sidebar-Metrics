using System.Threading.Channels;

namespace HardwareMonitor.Service.IPC;

public sealed class RequestQueue : IAsyncDisposable
{
    private readonly Channel<QueuedRequest> _channel;
    private readonly Func<QueuedRequest, CancellationToken, Task> _worker;
    private readonly CancellationTokenSource _cts = new();
    private readonly Task[] _workers;

    public RequestQueue(int capacity, int workerCount, Func<QueuedRequest, CancellationToken, Task> worker)
    {
        _channel = Channel.CreateBounded<QueuedRequest>(new BoundedChannelOptions(capacity)
        {
            FullMode = BoundedChannelFullMode.DropWrite,
            SingleReader = false,
            SingleWriter = false
        });
        _worker = worker;
        _workers = new Task[workerCount];
        for (int i = 0; i < workerCount; i++)
            _workers[i] = Task.Run(() => RunAsync(_cts.Token));
    }

    public bool TryEnqueue(QueuedRequest item)
    {
        return _channel.Writer.TryWrite(item);
    }

    private async Task RunAsync(CancellationToken cancellationToken)
    {
        await foreach (QueuedRequest item in _channel.Reader.ReadAllAsync(cancellationToken))
        {
            try { await _worker(item, cancellationToken).ConfigureAwait(false); }
            catch (Exception ex)
            {
                item.TrySetException(ex);
            }
        }
    }

    public async ValueTask DisposeAsync()
    {
        _channel.Writer.TryComplete();
        _cts.Cancel();
        try { await Task.WhenAll(_workers).ConfigureAwait(false); }
        catch (OperationCanceledException) { }
        _cts.Dispose();
    }
}

public sealed class QueuedRequest
{
    private readonly TaskCompletionSource<object> _completion =
        new(TaskCreationOptions.RunContinuationsAsynchronously);

    public QueuedRequest(string payload, object requestContext)
    {
        Payload = payload;
        RequestContext = requestContext;
    }

    public string Payload { get; }
    public object RequestContext { get; }

    public Task<object> Completion => _completion.Task;
    public bool TrySetResult(object value) => _completion.TrySetResult(value);
    public bool TrySetException(Exception exception) => _completion.TrySetException(exception);
}
