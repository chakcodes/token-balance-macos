#import <Foundation/Foundation.h>
#import "TokenBarCore.h"

@interface TBCodexAppServerHandshake : NSObject
- (NSArray<NSDictionary *> *)startMessages;
- (NSArray<NSDictionary *> *)messagesForResponse:(NSDictionary *)response error:(NSError **)error;
@end

static int failures = 0;

static void AssertEqual(NSString *actual, NSString *expected, NSString *name) {
    if (![actual isEqualToString:expected]) {
        fprintf(stderr, "FAIL %s: expected '%s', got '%s'\n", name.UTF8String, expected.UTF8String, actual.UTF8String);
        failures++;
    }
}

static void AssertTrue(BOOL value, NSString *name) {
    if (!value) {
        fprintf(stderr, "FAIL %s\n", name.UTF8String);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        NSDate *now = [NSDate dateWithTimeIntervalSince1970:1800000000];
        TBUsageSnapshot *normal = [[TBUsageSnapshot alloc] initWithProviderID:@"chatgpt"
            percentRemaining:@72 usesRemaining:@37
            resetsAt:[now dateByAddingTimeInterval:2 * 86400]
            extraResets:@[] capturedAt:now];
        TBMenuBarLabel *normalLabel = [TBMenuBarFormatter labelForSnapshot:normal now:now alertThreshold:86400];
        AssertEqual(normalLabel.text, @"72% · R×0 · —", @"normal label uses reset count and no expiry fallback");
        AssertTrue(normalLabel.kind == TBMenuBarLabelKindNormal, @"normal label kind");

        TBExtraReset *reset = [[TBExtraReset alloc] initWithID:@"r1" expiresAt:[now dateByAddingTimeInterval:8 * 3600]];
        TBUsageSnapshot *warning = [[TBUsageSnapshot alloc] initWithProviderID:@"chatgpt"
            percentRemaining:@72 usesRemaining:@37
            resetsAt:[now dateByAddingTimeInterval:2 * 86400]
            extraResets:@[reset] capturedAt:now];
        TBMenuBarLabel *warningLabel = [TBMenuBarFormatter labelForSnapshot:warning now:now alertThreshold:86400];
        AssertEqual(warningLabel.text, @"72% · R×1 · 8h", @"expiring reset uses fixed three-field layout");
        AssertTrue(warningLabel.kind == TBMenuBarLabelKindWarning, @"warning label kind");

        TBExtraReset *boundaryReset = [[TBExtraReset alloc] initWithID:@"boundary" expiresAt:[now dateByAddingTimeInterval:24 * 3600]];
        TBUsageSnapshot *boundary = [[TBUsageSnapshot alloc] initWithProviderID:@"chatgpt"
            percentRemaining:@72 usesRemaining:nil resetsAt:[now dateByAddingTimeInterval:7 * 86400]
            extraResets:@[boundaryReset] capturedAt:now];
        AssertEqual([TBMenuBarFormatter labelForSnapshot:boundary now:now alertThreshold:86400].text,
                    @"72% · R×1 · 24h", @"exactly twenty-four hours displays hours");

        TBExtraReset *futureReset = [[TBExtraReset alloc] initWithID:@"future" expiresAt:[now dateByAddingTimeInterval:3 * 86400]];
        TBUsageSnapshot *future = [[TBUsageSnapshot alloc] initWithProviderID:@"chatgpt"
            percentRemaining:@99 usesRemaining:nil resetsAt:[now dateByAddingTimeInterval:7 * 86400]
            extraResets:@[futureReset] capturedAt:now];
        AssertEqual([TBMenuBarFormatter labelForSnapshot:future now:now alertThreshold:86400].text,
                    @"99% · R×1 · 3d", @"reset expiry is shown before alert threshold");

        TBUsageSnapshot *missing = [[TBUsageSnapshot alloc] initWithProviderID:@"chatgpt"
            percentRemaining:@72 usesRemaining:nil
            resetsAt:[now dateByAddingTimeInterval:3600]
            extraResets:@[] capturedAt:now];
        AssertEqual([TBMenuBarFormatter labelForSnapshot:missing now:now alertThreshold:3600].text,
                    @"72% · R×0 · —", @"missing reset expiry does not use weekly reset time");

        TBUsageSnapshot *stale = [[TBUsageSnapshot alloc] initWithProviderID:@"chatgpt"
            percentRemaining:@72 usesRemaining:@37
            resetsAt:[now dateByAddingTimeInterval:86400]
            extraResets:@[] capturedAt:[now dateByAddingTimeInterval:-7201]];
        TBMenuBarLabel *staleLabel = [TBMenuBarFormatter labelForSnapshot:stale now:now alertThreshold:3600];
        AssertEqual(staleLabel.text, @"72% · R×0 · — ↻", @"stale label marker");
        AssertTrue(staleLabel.stale, @"stale flag");

        NSData *canonicalData = [@"{\"provider\":\"chatgpt\",\"weekly\":{\"percentRemaining\":72,\"usesRemaining\":37,\"resetsAt\":\"2027-01-17T10:00:00Z\"},\"extraResets\":[{\"id\":\"r1\",\"expiresAt\":\"2027-01-16T18:00:00Z\"}],\"capturedAt\":\"2027-01-15T10:00:00Z\",\"ignored\":true}" dataUsingEncoding:NSUTF8StringEncoding];
        NSError *parseError = nil;
        TBUsageSnapshot *parsed = [TBChatGPTSnapshotParser snapshotFromData:canonicalData error:&parseError];
        AssertTrue(parsed != nil && parseError == nil, @"canonical JSON parses");
        AssertTrue([parsed.percentRemaining isEqual:@72] && [parsed.usesRemaining isEqual:@37], @"canonical weekly values");
        AssertTrue(parsed.extraResets.count == 1, @"canonical extra reset");

        NSData *snakeData = [@"{\"weekly\":{\"percent_remaining\":65,\"resets_at\":\"2027-01-17T10:00:00Z\"},\"extra_resets\":[],\"captured_at\":\"2027-01-15T10:00:00Z\"}" dataUsingEncoding:NSUTF8StringEncoding];
        TBUsageSnapshot *snake = [TBChatGPTSnapshotParser snapshotFromData:snakeData error:&parseError];
        AssertTrue([snake.percentRemaining isEqual:@65], @"snake case percentage");
        AssertTrue(snake.usesRemaining == nil, @"omitted use count stays nil");

        NSData *badDateData = [@"{\"weekly\":{\"percentRemaining\":72,\"resetsAt\":\"not-a-date\"}}" dataUsingEncoding:NSUTF8StringEncoding];
        TBUsageSnapshot *badDate = [TBChatGPTSnapshotParser snapshotFromData:badDateData error:&parseError];
        AssertTrue(badDate == nil && parseError != nil, @"malformed reset date is rejected");

        TBAlertSettings *alertSettings = [[TBAlertSettings alloc] initWithLowPercentThreshold:10 resetExpiryThreshold:86400];
        TBUsageSnapshot *lowAndExpiring = [[TBUsageSnapshot alloc] initWithProviderID:@"chatgpt"
            percentRemaining:@8 usesRemaining:@3 resetsAt:[now dateByAddingTimeInterval:86400]
            extraResets:@[reset] capturedAt:now];
        NSArray<TBUsageAlert *> *alerts = [TBAlertEvaluator alertsForSnapshot:lowAndExpiring now:now settings:alertSettings];
        AssertTrue(alerts.count == 2, @"low allowance and expiring reset produce two alerts");
        NSSet *alertIDs = [NSSet setWithArray:[alerts valueForKey:@"identifier"]];
        AssertTrue([alertIDs containsObject:@"weekly-low-8"], @"low alert has stable dedupe ID");
        AssertTrue([alertIDs containsObject:@"reset-expiring-r1"], @"reset alert has stable dedupe ID");

        TBUsageSnapshot *healthy = [[TBUsageSnapshot alloc] initWithProviderID:@"chatgpt"
            percentRemaining:@72 usesRemaining:@37 resetsAt:[now dateByAddingTimeInterval:86400]
            extraResets:@[] capturedAt:now];
        AssertTrue([TBAlertEvaluator alertsForSnapshot:healthy now:now settings:alertSettings].count == 0,
                   @"healthy snapshot produces no alerts");

        NSData *appServerData = [@"{\"id\":2,\"result\":{\"rateLimits\":{\"limitId\":\"codex\",\"primary\":{\"usedPercent\":35,\"windowDurationMins\":10080,\"resetsAt\":1800500000},\"planType\":\"plus\"},\"rateLimitResetCredits\":{\"availableCount\":2,\"credits\":[{\"id\":\"credit-1\",\"status\":\"available\",\"expiresAt\":1800100000},{\"id\":\"credit-2\",\"status\":\"available\",\"expiresAt\":1800200000}]}}}" dataUsingEncoding:NSUTF8StringEncoding];
        TBUsageSnapshot *automatic = [TBCodexRateLimitParser snapshotFromResponseData:appServerData capturedAt:now error:&parseError];
        AssertTrue([automatic.percentRemaining isEqual:@65], @"app-server used percentage converts to remaining");
        AssertTrue(automatic.usesRemaining == nil, @"app-server does not invent remaining uses");
        AssertTrue(automatic.extraResets.count == 2, @"app-server reads available reset details");
        AssertTrue([automatic.resetsAt isEqualToDate:[NSDate dateWithTimeIntervalSince1970:1800500000]], @"app-server reads weekly reset date");
        AssertEqual([TBMenuBarFormatter labelForSnapshot:automatic now:now alertThreshold:3600].text,
                    @"65% · R×2 · 2d", @"automatic label uses nearest reset expiry instead of weekly reset");

        NSArray<NSString *> *codexPaths = [TBCodexAppServerProvider candidateExecutablePaths];
        AssertTrue([codexPaths containsObject:@"/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"],
                   @"provider supports ChatGPT 26.924 bundled CLI path");
        AssertTrue([codexPaths containsObject:@"/Applications/ChatGPT.app/Contents/Resources/codex"],
                   @"provider preserves legacy bundled CLI path");
        AssertTrue([codexPaths indexOfObject:@"/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"] <
                   [codexPaths indexOfObject:@"/Applications/ChatGPT.app/Contents/Resources/codex"],
                   @"provider prefers native current CLI over legacy CLI");

        TBCodexAppServerHandshake *handshake = [TBCodexAppServerHandshake new];
        NSArray<NSDictionary *> *startMessages = [handshake startMessages];
        AssertTrue(startMessages.count == 1 && [startMessages.firstObject[@"method"] isEqual:@"initialize"],
                   @"app-server starts with initialize only");
        NSError *handshakeError = nil;
        NSArray<NSDictionary *> *followupMessages = [handshake messagesForResponse:@{@"id": @1, @"result": @{}} error:&handshakeError];
        AssertTrue(handshakeError == nil && followupMessages.count == 2 &&
                   [followupMessages[0][@"method"] isEqual:@"initialized"] &&
                   [followupMessages[1][@"method"] isEqual:@"account/rateLimits/read"],
                   @"successful initialize sends initialized before rate-limit read");
        TBCodexAppServerHandshake *failedHandshake = [TBCodexAppServerHandshake new];
        NSError *initializeError = nil;
        NSArray<NSDictionary *> *failedMessages = [failedHandshake messagesForResponse:@{@"id": @1, @"error": @{@"message": @"unsupported"}} error:&initializeError];
        AssertTrue(failedMessages.count == 0 && initializeError != nil &&
                   [initializeError.localizedDescription isEqual:@"unsupported"],
                   @"initialize error stops request sequence with diagnostic");

        TBWatcherPolicy *policy = [TBWatcherPolicy new];
        AssertTrue([policy initialActionWithChatGPTRunning:YES tokenBarRunning:NO] == TBWatcherActionLaunchTokenBar,
                   @"watcher launches TokenBar when ChatGPT is already running");
        [policy tokenBarDidTerminateWhileChatGPTRunning:YES];
        AssertTrue(policy.suppressedUntilNextChatGPTLaunch, @"manual TokenBar quit suppresses relaunch in current ChatGPT session");
        AssertTrue([policy chatGPTDidLaunchWithTokenBarRunning:NO] == TBWatcherActionNone,
                   @"duplicate launch event respects manual quit suppression");
        AssertTrue([policy chatGPTDidTerminateWithTokenBarRunning:NO] == TBWatcherActionNone,
                   @"ChatGPT termination clears suppression without redundant termination");
        AssertTrue([policy chatGPTDidLaunchWithTokenBarRunning:NO] == TBWatcherActionLaunchTokenBar,
                   @"next ChatGPT session launches TokenBar again");
        AssertTrue([policy chatGPTDidTerminateWithTokenBarRunning:YES] == TBWatcherActionTerminateTokenBar,
                   @"ChatGPT termination closes running TokenBar");

        if (failures == 0) printf("PASS TokenBarCoreTests (38 assertions)\n");
        return failures == 0 ? 0 : 1;
    }
}
