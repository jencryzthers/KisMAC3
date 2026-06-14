/*
 File:        KMProtocolMetadata.h
 Program:     KisMac3
 Slice:       S2.1 - Modern protocol metadata model

 Description: A clean, additive metadata type that decodes the tagged
              parameters (information elements) of an 802.11 management frame
              (beacon / probe-response / assoc-request) and classifies the
              network's modern security posture and PHY generation.

              This is OFFLINE / PASSIVE decode of *already-parsed* frame bytes
              (imported pcaps). It performs no radio I/O whatsoever.

              The TLV walker is fully bounds-checked: truncated, malformed, and
              vendor-specific elements are skipped, never dereferenced past the
              supplied buffer. It must not crash on adversarial input.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Modern security posture decoded from the RSN IE (id 48) and the vendor WPA
/// IE (id 221, MS OUI). This is ORTHOGONAL to the legacy `encryptionType`
/// (which only distinguishes none/WEP/WPA/WPA2/LEAP). It refines WPA2+ networks.
typedef NS_ENUM(NSInteger, KMSecurityMode) {
    KMSecurityModeUnknown = 0,   ///< No RSN/WPA IE seen yet (or not a mgmt frame).
    KMSecurityModeOpen,          ///< No privacy, no RSN/WPA IE.
    KMSecurityModeWEP,           ///< Privacy bit set but no RSN/WPA IE.
    KMSecurityModeWPA,           ///< Vendor WPA IE only (WPA1/TKIP era).
    KMSecurityModeWPA2,          ///< RSN IE with PSK AKM (00-0F-AC:2).
    KMSecurityModeWPA2Enterprise,///< RSN IE with 802.1X AKM (00-0F-AC:1/5).
    KMSecurityModeWPA3SAE,       ///< RSN IE with SAE AKM only (00-0F-AC:8).
    KMSecurityModeWPA3Transition,///< RSN IE advertising BOTH PSK and SAE AKM.
    KMSecurityModeWPA3Enterprise,///< RSN IE with 802.1X-SHA256/SuiteB AKM (00-0F-AC:11/12).
    KMSecurityModeOWE,           ///< RSN IE with OWE AKM (00-0F-AC:18) - Enhanced Open.
    KMSecurityModeEnterprise,    ///< Generic 802.1X (mixed/other EAP) AKM.
};

/// Protected Management Frames (802.11w) posture from RSN capabilities.
typedef NS_ENUM(NSInteger, KMPMFMode) {
    KMPMFModeUnknown = 0, ///< No RSN IE / not decoded.
    KMPMFModeDisabled,    ///< RSN present, neither MFPC nor MFPR set.
    KMPMFModeCapable,     ///< MFPC set (capable, not required).
    KMPMFModeRequired,    ///< MFPR set (required).
};

/// PHY generation classified from HT/VHT/HE/EHT capability elements.
typedef NS_ENUM(NSInteger, KMPHYGeneration) {
    KMPHYGenerationUnknown = 0, ///< No PHY capability element seen.
    KMPHYGenerationLegacy,      ///< a/b/g only (no HT/VHT/HE/EHT).
    KMPHYGenerationWiFi4,       ///< HT (802.11n, id 45).
    KMPHYGenerationWiFi5,       ///< VHT (802.11ac, id 191).
    KMPHYGenerationWiFi6,       ///< HE (802.11ax, ext id 35) on 2.4/5 GHz.
    KMPHYGenerationWiFi6E,      ///< HE + 6 GHz operation (ext id 59).
    KMPHYGenerationWiFi7,       ///< EHT (802.11be, ext id 108).
};

#pragma mark - KMProtocolMetadata

@interface KMProtocolMetadata : NSObject

/// Modern security mode (refines the legacy encryptionType).
@property (nonatomic, readonly) KMSecurityMode securityMode;
/// 802.11w / PMF posture.
@property (nonatomic, readonly) KMPMFMode pmfMode;
/// PHY generation (Wi-Fi 4..7).
@property (nonatomic, readonly) KMPHYGeneration phyGeneration;

/// Widest channel width advertised in HT/VHT/HE/EHT operation/caps, in MHz
/// (20/40/80/160/320), or 0 if not determinable.
@property (nonatomic, readonly) NSInteger channelWidthMHz;

/// YES iff a zero-length or all-NUL SSID element was seen (hidden network).
@property (nonatomic, readonly) BOOL isHiddenSSID;

/// YES iff the network operates in the 6 GHz band (HE 6 GHz operation IE).
@property (nonatomic, readonly) BOOL is6GHz;

/// Whether any modern (RSN/PHY) element was actually decoded. If NO, callers
/// should fall back to the legacy encryptionType for display.
@property (nonatomic, readonly) BOOL didDecodeAnything;

/// Human-readable security string, e.g. "WPA3-SAE (PMF required)".
@property (nonatomic, readonly) NSString *securityDisplayString;
/// Human-readable PHY string, e.g. "Wi-Fi 6E (160 MHz)".
@property (nonatomic, readonly) NSString *phyDisplayString;

#pragma mark Decoding

/// Decodes the tagged-parameter (information element) region of a management
/// frame. `ies` points at the first element's id byte; `length` is the number
/// of bytes remaining in the frame from that point. `privacyBit` is the
/// Capability Info Privacy bit (so WEP-vs-open can be distinguished when no
/// RSN/WPA IE is present). Bounds-checked: safe on truncated/malformed input.
+ (instancetype)metadataFromInformationElements:(const uint8_t *)ies
                                          length:(NSInteger)length
                                      privacyBit:(BOOL)privacyBit;

/// Merge another decode into this one (the network sees many frames over time;
/// keep the strongest/most-specific signal). Returns YES if anything changed.
- (BOOL)mergeWith:(KMProtocolMetadata *)other;

@end

NS_ASSUME_NONNULL_END
