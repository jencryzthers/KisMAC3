/*
 File:        KMLANService.h
 Program:     KisMac3
 Slice:       S3.3 - LAN discovery (Bonjour/mDNS/DNS-SD)

 Description: Clean model object for one Bonjour / DNS-SD service instance
              discovered passively on the local network via NWBrowser
              (Network.framework). Holds the facts a recon UI / report needs:
              the service instance name, the DNS-SD service type
              (e.g. "_http._tcp"), the browse domain (usually "local."), and -
              where the OS resolves the instance - the target host, port, and
              the resolved IP address strings.

              PASSIVE ONLY: this model is produced by listening to mDNS/DNS-SD
              announcements the OS already receives. KisMAC NEVER actively probes,
              connects to, or pings any host - it only inventories what advertises
              itself. No stealth behavior.

              PRIVACY: a Bonjour instance name often embeds a personal device
              name ("Jean's MacBook Pro"), and host/IP are sensitive local
              identifiers. The model stores the raw values (it is what mDNS
              exposes) but -redactedDescriptionWithSettings: masks the
              hostname/instance/IP via the S4.1 KMRedactionSettings so logs /
              reports never have to dump them unredacted. The default
              -description is the fully-redacted form (safe for logs).

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

@class KMRedactionSettings;

NS_ASSUME_NONNULL_BEGIN

@interface KMLANService : NSObject

/// The DNS-SD service instance name (e.g. "Office Printer"). SENSITIVE: often
/// embeds a personal device/owner name.
@property (nonatomic, copy, nullable) NSString *name;

/// The DNS-SD service type (e.g. "_http._tcp", "_ssh._tcp"). Not personal.
@property (nonatomic, copy) NSString *type;

/// The browse domain (usually "local."). Not personal.
@property (nonatomic, copy) NSString *domain;

/// Resolved target hostname (e.g. "Jeans-MacBook.local."), or nil when the OS
/// has not (yet) resolved the instance. SENSITIVE.
@property (nonatomic, copy, nullable) NSString *hostName;

/// Resolved TCP/UDP port, or 0 when unresolved.
@property (nonatomic, assign) NSUInteger port;

/// Resolved IP address strings (IPv4/IPv6), or empty when unresolved. SENSITIVE.
@property (nonatomic, copy) NSArray<NSString *> *ipAddresses;

/// YES once the instance has been resolved to at least a host or address.
@property (nonatomic, readonly) BOOL isResolved;

/// A stable identity key (type + name + domain) used to de-dupe instances.
@property (nonatomic, readonly) NSString *identityKey;

/// A plain (UNREDACTED) dictionary representation for in-memory use / export
/// where the caller is responsible for redaction.
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

/// A redaction-aware one-line description. When `settings` redacts hostnames
/// the instance name, hostname and IPs are masked; pass nil to get the fully
/// redacted form (safe default for logs).
- (NSString *)redactedDescriptionWithSettings:(nullable KMRedactionSettings *)settings;

@end

NS_ASSUME_NONNULL_END
