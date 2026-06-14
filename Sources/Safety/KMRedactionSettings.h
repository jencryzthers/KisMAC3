/*
 File:        KMRedactionSettings.h
 Program:     KisMac3
 Slice:       S4.1 - Campaign scope + audit log + emergency stop

 Description: Redaction settings + transform (Milestone 9). Independently
              toggleable masking of:
                - MAC addresses        (BSSIDs, client/station MACs)
                - SSIDs                (network names)
                - hostnames            (DNS / Bonjour names)
                - Bluetooth identifiers (BLE UUIDs / addresses)

              The transform here is the PRIMITIVE: -redactString: masks any
              occurrences found in arbitrary text, and the typed helpers
              (-redactMAC:, -redactSSID:, ...) mask a single known value.
              Full report-wide application lands with S6.x; this slice provides
              the utility + the settings model with SAFE behavior (redaction is
              order-stable and never throws).

              Masking style: identifying bytes are replaced with '*' while
              keeping enough shape to stay debuggable but non-identifying, e.g.
                MAC   00:11:22:33:44:55 -> 00:11:**:**:**:** (vendor OUI kept,
                                            device portion masked)
                SSID  "HomeNet"         -> "H*****t" (first/last kept)
                host  printer.local     -> "p*****r.local" (label masked, TLD kept)

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KMRedactionSettings : NSObject <NSSecureCoding, NSCopying>

/// Master switch. When NO, every -redact* method returns its input verbatim
/// regardless of the per-type flags below.
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;

/// Per-type toggles (only consulted when `enabled` is YES). All default YES so
/// that turning the master switch on is privacy-safe by default.
@property (nonatomic, assign) BOOL redactMACAddresses;
@property (nonatomic, assign) BOOL redactSSIDs;
@property (nonatomic, assign) BOOL redactHostnames;
@property (nonatomic, assign) BOOL redactBluetoothIdentifiers;

/// Default settings: redaction OFF (parity with current behavior). The caller
/// turns it on; when on, all four categories redact.
+ (instancetype)defaultSettings;

#pragma mark Typed single-value redaction

/// Mask a MAC/BSSID, keeping the 3-byte OUI for vendor context. Returns input
/// unchanged when disabled or the per-type flag is off.
- (NSString *)redactMAC:(nullable NSString *)mac;
/// Mask an SSID keeping first/last char.
- (NSString *)redactSSID:(nullable NSString *)ssid;
/// Mask a hostname's leftmost label, keeping any domain suffix.
- (NSString *)redactHostname:(nullable NSString *)hostname;
/// Mask a Bluetooth identifier (UUID or address).
- (NSString *)redactBluetoothIdentifier:(nullable NSString *)identifier;

#pragma mark Free-text redaction

/// Scan arbitrary text and mask any MAC addresses (and, when the SSID/host
/// flags are on, anything that pattern-matches). MAC masking is the reliable
/// case; SSIDs/hostnames in free text are masked only via the typed helpers /
/// explicit value list since they are not safely pattern-detectable. Returns
/// input verbatim when disabled.
- (NSString *)redactString:(nullable NSString *)text;

/// Convenience: applies the typed helpers to known values inside `text` by
/// literal substitution (used where the caller knows the SSID/host strings).
- (NSString *)redactString:(nullable NSString *)text
              knownSSIDs:(nullable NSArray<NSString *> *)ssids
           knownHostnames:(nullable NSArray<NSString *> *)hostnames;

@end

NS_ASSUME_NONNULL_END
