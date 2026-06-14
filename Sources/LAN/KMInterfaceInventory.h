/*
 File:        KMInterfaceInventory.h
 Program:     KisMac3
 Slice:       S3.4 - Local interface inventory

 Description: Read-only one-shot collector that enumerates the local network
              interfaces on THIS Mac via getifaddrs(3), coalesces the per-family
              ifaddrs entries (link-layer / AF_INET / AF_INET6) into one
              KMNetworkInterface per BSD name, classifies each interface
              (Wi-Fi / Ethernet / Thunderbolt-bridge / VPN / AWDL / loopback /
              other) from its BSD name + flags, and (where cheap) cross-checks
              the Wi-Fi interface name against CoreWLAN. It also marks the
              system's active/primary interface via SystemConfiguration's
              global IPv4 state (the interface carrying the default route).

              READ-ONLY / LOCAL-ONLY: reads the kernel's own interface table and
              the SCDynamicStore global state. It NEVER configures an interface,
              sends traffic, or probes a host. macOS needs no authorization for
              this, so the feature is always available.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

@class KMNetworkInterface;

NS_ASSUME_NONNULL_BEGIN

@interface KMInterfaceInventory : NSObject

/// One-shot read-only enumeration of every local interface, most-useful-first
/// (primary, then up-with-IP, then the rest). Returns [] on error (never nil,
/// never throws).
+ (NSArray<KMNetworkInterface *> *)currentInterfaces;

/// The BSD name of the system's active/primary interface (the one carrying the
/// default IPv4 route per SystemConfiguration), or nil if none / unavailable.
+ (nullable NSString *)primaryInterfaceName;

/// The CoreWLAN default Wi-Fi interface name (e.g. "en0"), or nil if CoreWLAN
/// exposes none. Used to harden the Wi-Fi classification cheaply.
+ (nullable NSString *)wiFiInterfaceName;

@end

NS_ASSUME_NONNULL_END
