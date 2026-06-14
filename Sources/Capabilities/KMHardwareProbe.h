/*
 File:        KMHardwareProbe.h
 Program:     KisMac3
 Slice:       S1.1 - MacBook hardware capability probe

 Description: Non-disruptive hardware/OS capability probe for the modern
              macOS port. It inspects what THIS Mac and macOS version actually
              allow and emits a persisted report of KMHardwareCapability
              objects plus host metadata.

 SAFETY: This probe is non-disruptive by default. It NEVER disconnects Wi-Fi,
         enters monitor mode, switches channels, creates an AP, or injects
         frames. Disruptive capabilities are REPORTED as
         KMCapabilityStatusUnknownRequiresActiveProbe with a reason -- they are
         not executed. A future, explicitly user-consented active probe (a
         later slice) would be the only place those are exercised.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>
#import "KMHardwareCapability.h"

NS_ASSUME_NONNULL_BEGIN

@interface KMHardwareProbe : NSObject

/// Mac model identifier, e.g. "MacBookPro18,3" (sysctl hw.model).
@property (nonatomic, copy, readonly) NSString *hardwareModel;
/// macOS version string, e.g. "27.0.0".
@property (nonatomic, copy, readonly) NSString *osVersion;
/// CPU architecture, e.g. "arm64" or "x86_64".
@property (nonatomic, copy, readonly) NSString *architecture;
/// App short version + build, e.g. "0.3.4 (Alpha 4)".
@property (nonatomic, copy, readonly) NSString *appBuild;
/// Capabilities from the last run. Empty until -runProbe is called.
@property (nonatomic, copy, readonly) NSArray<KMHardwareCapability *> *capabilities;

/// Runs every non-disruptive check synchronously and populates -capabilities.
/// Returns the capability array. Safe to call on a background queue.
- (NSArray<KMHardwareCapability *> *)runProbe;

/// Full report dictionary (host metadata + timestamp + capability list).
- (NSDictionary<NSString *, id> *)reportDictionary;

/// Path where the report is persisted for this Mac model + OS version:
/// ~/Library/Application Support/KisMac3/hardware-probe-<model>-<os>.json
- (NSString *)persistedReportPath;

/// Writes -reportDictionary as JSON to -persistedReportPath. Returns YES on
/// success; on failure populates *error and returns NO.
- (BOOL)persistReport:(NSError **)error;

/// One-line human summary suitable for DBNSLog/NSLog.
- (NSString *)logSummary;

/// Convenience: probe + persist + log, off the main thread. Non-disruptive.
/// Call once at launch. Completion (if given) runs on the main queue.
+ (void)runProbeAsynchronouslyWithCompletion:(nullable void (^)(KMHardwareProbe *probe))completion;

@end

NS_ASSUME_NONNULL_END
