/*
 File:        KMAuditLog.h
 Program:     KisMac3
 Slice:       S4.1 - Campaign scope + audit log + emergency stop

 Description: Append-only LOCAL audit log (Milestone 9). Records active
              operations, scope changes, campaign arm/disarm, and the emergency
              stop. Each entry is one JSON object on its own line (.jsonl) so
              the log is append-only, human-readable, and never rewritten.

              Storage: Application Support/KisMac3/audit-YYYY-MM-DD.jsonl
              (local-only by default; never exported off-device unless the
              operator explicitly opts in elsewhere). The log RECORDS; it never
              silently drops -- a write failure is itself logged (DBNSLog) so a
              gap is observable.

              Redaction: the log can be written through a KMRedactionSettings
              transform so identifiers are masked at rest when redaction is on.
              Audit metadata (timestamps, action types) is never redacted.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

@class KMRedactionSettings;

NS_ASSUME_NONNULL_BEGIN

/// Canonical audit action types (stable strings for the "action" field).
extern NSString * const KMAuditActionCampaignArmed;
extern NSString * const KMAuditActionCampaignDisarmed;
extern NSString * const KMAuditActionScopeChanged;
extern NSString * const KMAuditActionEmergencyStop;
extern NSString * const KMAuditActionActiveOperation;   // an active/offensive op was attempted/run
extern NSString * const KMAuditActionSelfTest;          // self-test marker

@interface KMAuditLog : NSObject

/// Shared append-only log (writes to Application Support/KisMac3).
+ (instancetype)sharedLog;

/// Designated init for tests: write to an explicit directory.
- (instancetype)initWithDirectory:(NSURL *)directory NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// The redaction settings applied to identifier fields at write time. When nil
/// (default) entries are written verbatim. Audit metadata is never redacted.
@property (nonatomic, strong, nullable) KMRedactionSettings *redaction;

/// The directory the log is being written to.
@property (nonatomic, copy, readonly) NSURL *directory;
/// The current day's log file URL.
@property (nonatomic, copy, readonly) NSURL *currentLogFileURL;

/// Append an entry. `action` is one of the KMAuditAction* constants; `detail`
/// is a free-form human line; `context` is an optional dictionary of
/// JSON-safe values (scope summary, target, reason). Returns YES if persisted.
/// NEVER silently drops: on failure it DBNSLogs and returns NO.
- (BOOL)appendAction:(NSString *)action
              detail:(NSString *)detail
             context:(nullable NSDictionary<NSString *, id> *)context;

/// Read back all entries from the current log file (parsed JSON objects),
/// oldest first. Used by the self-test and by report assembly (S6.x).
- (NSArray<NSDictionary<NSString *, id> *> *)readCurrentEntries;

@end

NS_ASSUME_NONNULL_END
