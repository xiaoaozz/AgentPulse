using System.Text.Json;
using System.Text.Json.Serialization;
using System.IO.Pipes;
using System.Text;
using AgentPulse.Windows.Core.Models;
using AgentPulse.Windows.Core.Services;

var transportTests = new Func<Task>[]
{
    ValidMessageIsDeliveredAsync,
    MalformedMessageReportsErrorAndServerRecoversAsync,
    IdleDisposalCompletesPromptlyAsync,
    OversizedMessageReportsErrorAndServerRecoversAsync,
    IdleClientTimesOutAndLaterEventsStillFlowAsync,
    ConnectedIdleClientDoesNotBlockDisposalAsync,
};

var fixturePath = args.FirstOrDefault() ?? Path.Combine(
    AppContext.BaseDirectory,
    "..", "..", "..", "..", "..",
    "Protocol", "Fixtures", "session-scenarios.json");
var fixture = JsonSerializer.Deserialize<ProtocolFixture>(File.ReadAllText(fixturePath))
    ?? throw new InvalidOperationException("Could not decode shared AgentPulse protocol fixtures.");
AssertEqual(1, fixture.ProtocolVersion, "protocol version");

foreach (var scenario in fixture.Scenarios)
{
    var repository = new SessionRepository();
    foreach (var value in scenario.Events) repository.Receive(value);
    AssertSequence(scenario.ExpectedOrder, repository.Sessions.Select(value => value.Id), scenario.Name);
    AssertEqual(scenario.ExpectedOngoingCount, repository.OngoingCount, $"{scenario.Name}: ongoing count");
    AssertEqual(scenario.ExpectedClearableCount, repository.ClearableCount, $"{scenario.Name}: clearable count");
    if (scenario.ExpectedPhases is not null)
    {
        foreach (var pair in scenario.ExpectedPhases)
        {
            var phase = repository.Sessions.FirstOrDefault(value => value.Id == pair.Key)?.Phase;
            AssertEqual(pair.Value, phase?.ToString().ToLowerInvariant(), $"{scenario.Name}: {pair.Key} phase");
        }
    }
    foreach (var id in scenario.RemoveIds) repository.RemoveCompletedSession(id);
    AssertSequence(
        scenario.ExpectedOrderAfterRemovals,
        repository.Sessions.Select(value => value.Id),
        $"{scenario.Name}: protected removals");
}

foreach (var test in transportTests) await test();

Console.WriteLine(
    $"Passed {fixture.Scenarios.Count} shared AgentPulse protocol scenario(s) and {transportTests.Length} named-pipe integration test(s).");
return;

static async Task ValidMessageIsDeliveredAsync()
{
    var pipeName = UniquePipeName();
    var received = new TaskCompletionSource<AgentEvent>(TaskCreationOptions.RunContinuationsAsynchronously);
    await using var server = new NamedPipeEventServer(received.SetResult, error => throw new InvalidOperationException("Unexpected pipe error.", error), pipeName);
    server.Start();

    await SendRawAsync(pipeName, """
        {"session_id":"valid-message","agent":"Codex","cwd":"C:\\work","title":"Task","phase":"done","detail":"Delivered"}
        """);

    var value = await WaitAsync(received.Task, "valid named-pipe delivery");
    AssertEqual("valid-message", value.SessionId, "valid named-pipe session");
    AssertEqual("done", value.Phase, "valid named-pipe phase");
    AssertEqual("Delivered", value.Detail, "valid named-pipe detail");
}

static async Task MalformedMessageReportsErrorAndServerRecoversAsync()
{
    var pipeName = UniquePipeName();
    var received = new TaskCompletionSource<AgentEvent>(TaskCreationOptions.RunContinuationsAsynchronously);
    var errors = new TaskCompletionSource<Exception>(TaskCreationOptions.RunContinuationsAsynchronously);
    var errorCount = 0;
    await using var server = new NamedPipeEventServer(
        value => received.TrySetResult(value),
        error =>
        {
            if (Interlocked.Increment(ref errorCount) == 1) errors.TrySetResult(error);
        },
        pipeName);
    server.Start();

    await SendRawAsync(pipeName, "{");
    var decodeError = await WaitAsync(errors.Task, "malformed named-pipe error");
    AssertTrue(decodeError is JsonException, "malformed payload should report a JSON error");

    await SendRawAsync(pipeName, """
        {"session_id":"recovered-message","agent":"Codex","cwd":"C:\\work","phase":"running","detail":"Recovered"}
        """);

    var value = await WaitAsync(received.Task, "named-pipe recovery delivery");
    AssertEqual("recovered-message", value.SessionId, "recovered named-pipe session");
    AssertEqual("running", value.Phase, "recovered named-pipe phase");
    AssertEqual(1, errorCount, "malformed named-pipe error count");
}

static async Task IdleDisposalCompletesPromptlyAsync()
{
    var pipeName = UniquePipeName();
    await using var server = new NamedPipeEventServer(_ => { }, _ => { }, pipeName);
    server.Start();
    await WaitAsync(server.DisposeAsync().AsTask(), "idle pipe disposal");
}

static async Task OversizedMessageReportsErrorAndServerRecoversAsync()
{
    var pipeName = UniquePipeName();
    var received = new TaskCompletionSource<AgentEvent>(TaskCreationOptions.RunContinuationsAsynchronously);
    var errors = new TaskCompletionSource<Exception>(TaskCreationOptions.RunContinuationsAsynchronously);
    var errorCount = 0;
    await using var server = new NamedPipeEventServer(
        value => received.TrySetResult(value),
        error =>
        {
            if (Interlocked.Increment(ref errorCount) == 1) errors.TrySetResult(error);
        },
        pipeName);
    server.Start();

    var oversized = new string('x', NamedPipeEventServer.MaxMessageBytes);
    await SendRawAsync(pipeName,
        $$"""{"session_id":"too-large","agent":"Codex","cwd":"C:\\work","phase":"running","detail":"{{oversized}}"}""");

    var error = await WaitAsync(errors.Task, "oversized named-pipe error");
    AssertTrue(error is InvalidDataException, "oversized payload should report a size error");

    await SendRawAsync(pipeName, """
        {"session_id":"post-oversize","agent":"Codex","cwd":"C:\\work","phase":"done"}
        """);
    var recovered = await WaitAsync(received.Task, "oversized named-pipe recovery");
    AssertEqual("post-oversize", recovered.SessionId, "oversized recovery session");
    AssertEqual(1, errorCount, "oversized named-pipe error count");
}

static async Task IdleClientTimesOutAndLaterEventsStillFlowAsync()
{
    var pipeName = UniquePipeName();
    var received = new TaskCompletionSource<AgentEvent>(TaskCreationOptions.RunContinuationsAsynchronously);
    var errors = new TaskCompletionSource<Exception>(TaskCreationOptions.RunContinuationsAsynchronously);
    var errorCount = 0;
    await using var server = new NamedPipeEventServer(
        value => received.TrySetResult(value),
        error =>
        {
            if (Interlocked.Increment(ref errorCount) == 1) errors.TrySetResult(error);
        },
        pipeName);
    server.Start();

    await using var idleClient = await ConnectAsync(pipeName);
    var error = await WaitAsync(errors.Task, "idle named-pipe timeout");
    AssertTrue(error is TimeoutException or OperationCanceledException, "idle client should report a timeout-like error");
    await idleClient.DisposeAsync();

    await SendRawAsync(pipeName, """
        {"session_id":"post-timeout","agent":"Codex","cwd":"C:\\work","phase":"done","detail":"Recovered after timeout"}
        """);
    var recovered = await WaitAsync(received.Task, "idle named-pipe recovery");
    AssertEqual("post-timeout", recovered.SessionId, "idle timeout recovery session");
    AssertEqual(1, errorCount, "idle named-pipe error count");
}

static async Task ConnectedIdleClientDoesNotBlockDisposalAsync()
{
    var pipeName = UniquePipeName();
    var errors = new TaskCompletionSource<Exception>(TaskCreationOptions.RunContinuationsAsynchronously);
    await using var server = new NamedPipeEventServer(_ => { }, error => errors.TrySetResult(error), pipeName);
    server.Start();

    await using var idleClient = await ConnectAsync(pipeName);
    var disposeTask = server.DisposeAsync().AsTask();
    await WaitAsync(disposeTask, "connected idle pipe disposal");
}

static async Task<NamedPipeClientStream> ConnectAsync(string pipeName)
{
    var client = new NamedPipeClientStream(".", pipeName, PipeDirection.Out, PipeOptions.Asynchronous);
    await client.ConnectAsync(3_000);
    return client;
}

static async Task SendRawAsync(string pipeName, string payload)
{
    await using var client = await ConnectAsync(pipeName);
    var bytes = Encoding.UTF8.GetBytes(payload);
    await client.WriteAsync(bytes);
    await client.FlushAsync();
}

static async Task<T> WaitAsync<T>(Task<T> task, string context) =>
    await task.WaitAsync(TimeSpan.FromSeconds(3))
    ?? throw new InvalidOperationException($"{context} unexpectedly completed without a result.");

static async Task WaitAsync(Task task, string context)
{
    try
    {
        await task.WaitAsync(TimeSpan.FromSeconds(3));
    }
    catch (TimeoutException error)
    {
        throw new InvalidOperationException($"{context} timed out.", error);
    }
}

static string UniquePipeName() => $"agentpulse-test-{Guid.NewGuid():N}";

static void AssertEqual<T>(T expected, T actual, string context) where T : notnull
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
        throw new InvalidOperationException($"{context}: expected {expected}, got {actual}");
}

static void AssertSequence(IEnumerable<string> expected, IEnumerable<string> actual, string context)
{
    var expectedValues = expected.ToArray();
    var actualValues = actual.ToArray();
    if (!expectedValues.SequenceEqual(actualValues))
        throw new InvalidOperationException(
            $"{context}: expected [{string.Join(", ", expectedValues)}], got [{string.Join(", ", actualValues)}]");
}

static void AssertTrue(bool condition, string context)
{
    if (!condition) throw new InvalidOperationException(context);
}

internal sealed class ProtocolFixture
{
    [JsonPropertyName("protocol_version")]
    public int ProtocolVersion { get; init; }

    [JsonPropertyName("scenarios")]
    public List<SessionScenario> Scenarios { get; init; } = [];
}

internal sealed class SessionScenario
{
    [JsonPropertyName("name")]
    public string Name { get; init; } = "unnamed scenario";

    [JsonPropertyName("events")]
    public List<AgentEvent> Events { get; init; } = [];

    [JsonPropertyName("expected_order")]
    public List<string> ExpectedOrder { get; init; } = [];

    [JsonPropertyName("expected_phases")]
    public Dictionary<string, string>? ExpectedPhases { get; init; }

    [JsonPropertyName("expected_ongoing_count")]
    public int ExpectedOngoingCount { get; init; }

    [JsonPropertyName("expected_clearable_count")]
    public int ExpectedClearableCount { get; init; }

    [JsonPropertyName("remove_ids")]
    public List<string> RemoveIds { get; init; } = [];

    [JsonPropertyName("expected_order_after_removals")]
    public List<string> ExpectedOrderAfterRemovals { get; init; } = [];
}
