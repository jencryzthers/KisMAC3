/*
 File:        KMLANDiscovery.h
 Program:     KisMac3
 Slice:       S3.3 - LAN discovery (Bonjour/mDNS/DNS-SD)

 Description: Passive Bonjour / DNS-SD service-discovery manager built on the
              modern Network.framework browser (nw_browser). It browses a curated
              set of common DNS-SD service types on the local network
              ("local." domain), accumulates one KMLANService per discovered
              instance (de-duped by type+name+domain), and - where the OS resolves
              an instance - records the target host, port and IP addresses.

              PASSIVE ONLY / NO STEALTH: this manager only LISTENS to the
              mDNS/DNS-SD announcements the OS already receives. It NEVER actively
              probes, port-scans, pings, or connects to any host. An opt-in,
              default-OFF, rate-limited ping sweep is documented as a CLEARLY-GATED
              future hook only (see -pingSweepIsImplemented) - it is NOT
              implemented in this slice.

              LOCAL NETWORK PRIVACY: on modern macOS, Bonjour browsing triggers
              the system "Local Network" permission. The manager exposes the
              best-effort permission posture honestly via -localNetworkState; a
              denied state means the OS will silently return no results (the
              capability engine reports permissionMissing).

              NOTIFICATIONS: posts KMLANDiscoveryDidUpdateServicesNotification on
              the main thread when the discovered-service set changes. A delegate
              is also available for in-process consumers.

              PRIVACY: local-only; identifiers (instance names, hostnames, IPs)
              are sensitive and are redacted in this class's own logging via the
              S4.1 KMRedactionSettings.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

@class KMLANService;
@class KMLANDiscovery;

NS_ASSUME_NONNULL_BEGIN

/// Posted (main thread) when the discovered-service set changes.
extern NSString * const KMLANDiscoveryDidUpdateServicesNotification;

/// Best-effort Local Network permission posture. macOS does not expose a
/// queryable Local-Network authorization API the way it does for Location /
/// Bluetooth, so this is inferred from browser behavior: it starts UNKNOWN and
/// becomes ACTIVE once any browse result (including the "ready" state) is seen,
/// or DENIED if the browser fails to start / is cancelled with an error.
typedef NS_ENUM(NSInteger, KMLANNetworkState) {
    KMLANNetworkStateUnknown = 0, ///< Not yet determined (no browse started / no result yet).
    KMLANNetworkStateActive,      ///< Browser is running and returning results.
    KMLANNetworkStateDenied       ///< Browser failed/was blocked (likely Local Network denied).
};

/// Stable token for a network state (logging / persistence).
extern NSString *KMStringFromLANNetworkState(KMLANNetworkState state);

@protocol KMLANDiscoveryDelegate <NSObject>
@optional
- (void)lanDiscovery:(KMLANDiscovery *)discovery
   didUpdateServices:(NSArray<KMLANService *> *)services;
@end

@interface KMLANDiscovery : NSObject

@property (nonatomic, weak, nullable) id<KMLANDiscoveryDelegate> delegate;

/// Best-effort Local Network permission posture (see KMLANNetworkState).
@property (nonatomic, readonly) KMLANNetworkState localNetworkState;

/// YES while at least one browser is running.
@property (nonatomic, readonly, getter=isBrowsing) BOOL browsing;

/// The curated DNS-SD service types this manager browses (e.g. "_http._tcp").
+ (NSArray<NSString *> *)defaultServiceTypes;

/// Start passive Bonjour browsing of the default service types in "local.".
/// Idempotent (a second call while browsing is a no-op). Triggers the system
/// Local Network permission on first use.
- (void)startBrowsing;

/// Start passive Bonjour browsing of a specific set of service types.
- (void)startBrowsingServiceTypes:(NSArray<NSString *> *)serviceTypes;

/// Stop all browsing and tear down the browsers. Safe to call when not browsing.
- (void)stopBrowsing;

/// Snapshot of the services discovered so far (most-recently-seen first).
- (NSArray<KMLANService *> *)discoveredServices;

/// Clear the accumulated service set.
- (void)resetDiscoveredServices;

/// Future-hook honesty: the opt-in, rate-limited active ping sweep is NOT
/// implemented in this slice (passive Bonjour only, no stealth behavior).
/// Always returns NO. A future slice may add a clearly-gated, default-OFF sweep.
- (BOOL)pingSweepIsImplemented;

@end

NS_ASSUME_NONNULL_END
