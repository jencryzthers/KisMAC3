/*
 File:        KMLabEventLog.h
 Program:     KisMac3
 Slice:       S7.1 - Authorized-lab workflow core (Milestone 10)

 Description: The lab EVENT LOG: an in-memory, ordered collection of
              KMLabEvent observations parsed PASSIVELY from imported captures.
              This is the Milestone-10 "event log for probes, associations,
              disassociations, and handshakes" feature, built strictly on the
              existing OFFLINE pcap import path -- it never opens a radio.

              The log is fed one WavePacket at a time during import
              (-ingestImportedPacket:) and keeps the events it recognizes. It
              offers type/count summaries (for the campaign report) and a
              redaction-aware rendering.

              A shared instance (+sharedLog) lets the import path append without
              threading a reference through the whole call chain; tests build a
              private instance.

 SAFETY: PASSIVE. Observational evidence only. No transmit, no decision about
         capability/hardware, no live radio.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>
#import "KMLabEvent.h"

@class KMRedactionSettings;
@class WavePacket;

NS_ASSUME_NONNULL_BEGIN

/// Posted after a batch of imported events is appended. object = the log.
extern NSString * const KMLabEventLogDidChangeNotification;

@interface KMLabEventLog : NSObject

/// Shared in-memory event log (fed by the OFFLINE import path).
+ (instancetype)sharedLog;

/// All recorded events, oldest first.
@property (nonatomic, copy, readonly) NSArray<KMLabEvent *> *events;

/// Feed one already-parsed IMPORTED packet. If it is a management-frame /
/// handshake event we log, a KMLabEvent is appended and returned; otherwise
/// nil. PASSIVE: reads the packet's decoded fields, no radio.
- (nullable KMLabEvent *)ingestImportedPacket:(WavePacket *)packet;

/// Append a fully-built event (used by tests + the report assembler).
- (void)appendEvent:(KMLabEvent *)event;

/// Remove all events (e.g. before a fresh import in the self-test).
- (void)reset;

#pragma mark Summaries (for the campaign report)

/// Count of events of a given type.
- (NSUInteger)countOfType:(KMLabEventType)type;
/// Total number of events.
- (NSUInteger)count;
/// Number of distinct EAPOL/handshake observations (handshakes observed).
- (NSUInteger)handshakeCount;
/// type -> count dictionary (NSNumber keyed by KMLabEventType).
- (NSDictionary<NSNumber *, NSNumber *> *)countsByType;

/// A redaction-aware multiline summary (one line per event), honoring the
/// supplied KMRedactionSettings.
- (NSString *)redactedSummaryWithSettings:(nullable KMRedactionSettings *)settings;

@end

NS_ASSUME_NONNULL_END
