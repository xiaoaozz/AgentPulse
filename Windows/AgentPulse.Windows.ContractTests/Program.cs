using System.Text.Json;
using System.Text.Json.Serialization;
using AgentPulse.Windows.Core.Models;
using AgentPulse.Windows.Core.Services;

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
    foreach (var id in scenario.RemoveIds) repository.RemoveCompletedSession(id);
    AssertSequence(
        scenario.ExpectedOrderAfterRemovals,
        repository.Sessions.Select(value => value.Id),
        $"{scenario.Name}: protected removals");
}

Console.WriteLine($"Passed {fixture.Scenarios.Count} shared AgentPulse protocol scenario(s).");
return;

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

    [JsonPropertyName("expected_ongoing_count")]
    public int ExpectedOngoingCount { get; init; }

    [JsonPropertyName("expected_clearable_count")]
    public int ExpectedClearableCount { get; init; }

    [JsonPropertyName("remove_ids")]
    public List<string> RemoveIds { get; init; } = [];

    [JsonPropertyName("expected_order_after_removals")]
    public List<string> ExpectedOrderAfterRemovals { get; init; } = [];
}
