/*
 File:        KMNetworkInterface.h
 Program:     KisMac3
 Slice:       S3.4 - Local interface inventory

 Description: Clean model object for one local network interface as enumerated
              from getifaddrs(3) (with a CoreWLAN cross-check for the Wi-Fi
              interface name). Holds the facts a recon UI / report needs about
              each interface present on THIS Mac: the BSD name (en0, en1,
              utun3, awdl0, bridge0, lo0, ...), a classified type
              (Wi-Fi / Ethernet / Thunderbolt-bridge / VPN / AWDL-peer /
              loopback / other), the interface flags (up/running/broadcast/
              point-to-point), the link-layer MAC where present, the assigned
              IPv4/IPv6 addresses + netmasks, and whether it is the system's
              active/primary interface.

              READ-ONLY / LOCAL-ONLY: this model is produced by reading the
              kernel's own interface table (getifaddrs) - no configuration,
              no probing, no traffic. macOS requires no authorization for this.

              PRIVACY: a link-layer MAC and the assigned IP addresses are
              sensitive local identifiers. The model stores the raw values (it
              is what the kernel exposes locally) but -redactedDescriptionWithSettings:
              masks the MAC (via the S4.1 KMRedactionSettings MAC transform) and
              the IPs (via the hostname/IP transform) so logs / reports never
              have to dump them unredacted. The default -description is the
              fully-redacted form (safe for logs).

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

@class KMRedactionSettings;

NS_ASSUME_NONNULL_BEGIN

/// Classified interface type from BSD-name + flag heuristics.
typedef NS_ENUM(NSInteger, KMInterfaceType) {
    KMInterfaceTypeUnknown = 0,
    KMInterfaceTypeWiFi,                 // en0 (CoreWLAN-confirmed where cheap)
    KMInterfaceTypeEthernet,             // wired en*
    KMInterfaceTypeThunderboltBridge,    // bridge*, thunderbolt-bridge en[2-9]
    KMInterfaceTypeVPN,                  // utun*, ipsec*, ppp*
    KMInterfaceTypeAWDLPeer,             // awdl*, llw*
    KMInterfaceTypeLoopback,             // lo*
    KMInterfaceTypeOther,
};

/// Human-readable label for a type ("Wi-Fi", "Ethernet", ...). Never nil.
extern NSString *KMStringFromInterfaceType(KMInterfaceType type);

@interface KMNetworkInterface : NSObject

/// The BSD interface name (e.g. "en0", "utun3", "awdl0", "lo0"). Not personal.
@property (nonatomic, copy) NSString *bsdName;

/// Classified type.
@property (nonatomic, assign) KMInterfaceType type;

/// Interface flags (IFF_UP / IFF_RUNNING / IFF_BROADCAST / IFF_POINTOPOINT /
/// IFF_LOOPBACK), copied from the kernel's ifa_flags.
@property (nonatomic, assign) BOOL isUp;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) BOOL supportsBroadcast;
@property (nonatomic, assign) BOOL isPointToPoint;
@property (nonatomic, assign) BOOL isLoopback;

/// The raw flag bitfield (for diagnostics / dictionaryRepresentation).
@property (nonatomic, assign) NSUInteger flags;

/// Link-layer (MAC) address string "aa:bb:cc:dd:ee:ff", or nil when the
/// interface has no link-layer address (e.g. utun*, lo0). SENSITIVE.
@property (nonatomic, copy, nullable) NSString *macAddress;

/// Assigned IPv4 address strings. SENSITIVE.
@property (nonatomic, copy) NSArray<NSString *> *ipv4Addresses;
/// Assigned IPv6 address strings (scope id stripped for display). SENSITIVE.
@property (nonatomic, copy) NSArray<NSString *> *ipv6Addresses;
/// Netmask strings, parallel-indexed to ipv4Addresses where available.
@property (nonatomic, copy) NSArray<NSString *> *ipv4Netmasks;

/// YES when this interface is the system's active/primary interface (the one
/// carrying the default route), as reported by SystemConfiguration.
@property (nonatomic, assign) BOOL isPrimary;

/// YES once the interface has at least one assigned IP address.
@property (nonatomic, readonly) BOOL hasIPAddress;

/// A plain (UNREDACTED) dictionary representation for in-memory use / export
/// where the caller is responsible for redaction.
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

/// A redaction-aware one-line description. When `settings` redacts MACs /
/// hostnames the MAC and IPs are masked; pass nil to get the fully-redacted
/// form (safe default for logs).
- (NSString *)redactedDescriptionWithSettings:(nullable KMRedactionSettings *)settings;

@end

NS_ASSUME_NONNULL_END
