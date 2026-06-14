/*
 File:        KMLabEventLog.m
 Program:     KisMac3
 Slice:       S7.1 - Authorized-lab workflow core (Milestone 10)

 Description: See KMLabEventLog.h. PASSIVE, in-memory, import-fed.

 This file is part of KisMAC. GPL v2.
 */

#import "KMLabEventLog.h"
#import "../Safety/KMRedactionSettings.h"

NSString * const KMLabEventLogDidChangeNotification = @"KMLabEventLogDidChangeNotification";

@interface KMLabEventLog ()
@property (nonatomic, strong) NSMutableArray<KMLabEvent *> *mutableEvents;
@end

@implementation KMLabEventLog

+ (instancetype)sharedLog {
    static KMLabEventLog *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableEvents = [NSMutableArray array];
    }
    return self;
}

- (NSArray<KMLabEvent *> *)events {
    @synchronized (self) {
        return [self.mutableEvents copy];
    }
}

- (KMLabEvent *)ingestImportedPacket:(WavePacket *)packet {
    KMLabEvent *event = [KMLabEvent eventFromImportedPacket:packet];
    if (!event) return nil;
    [self appendEvent:event];
    return event;
}

- (void)appendEvent:(KMLabEvent *)event {
    if (![event isKindOfClass:[KMLabEvent class]]) return;
    @synchronized (self) {
        [self.mutableEvents addObject:event];
    }
    // Posting per-event would be noisy during a big import; observers poll on
    // import completion. We still post so live consumers (S5.x UI) can refresh.
    [[NSNotificationCenter defaultCenter] postNotificationName:KMLabEventLogDidChangeNotification object:self];
}

- (void)reset {
    @synchronized (self) {
        [self.mutableEvents removeAllObjects];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:KMLabEventLogDidChangeNotification object:self];
}

#pragma mark Summaries

- (NSUInteger)count {
    @synchronized (self) { return self.mutableEvents.count; }
}

- (NSUInteger)countOfType:(KMLabEventType)type {
    NSUInteger n = 0;
    for (KMLabEvent *e in self.events) {
        if (e.type == type) n++;
    }
    return n;
}

- (NSUInteger)handshakeCount {
    return [self countOfType:KMLabEventTypeEAPOLHandshake];
}

- (NSDictionary<NSNumber *, NSNumber *> *)countsByType {
    NSMutableDictionary<NSNumber *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    for (KMLabEvent *e in self.events) {
        NSNumber *key = @(e.type);
        counts[key] = @([counts[key] unsignedIntegerValue] + 1);
    }
    return counts;
}

- (NSString *)redactedSummaryWithSettings:(KMRedactionSettings *)settings {
    NSArray<KMLabEvent *> *evs = self.events;
    if (evs.count == 0) return @"(no events)";
    NSMutableString *s = [NSMutableString string];
    for (KMLabEvent *e in evs) {
        [s appendFormat:@"%@\n", [e redactedDescriptionWithSettings:settings]];
    }
    return s;
}

@end
