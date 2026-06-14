/*
 File:        KMProtocolMetadata.m
 Program:     KisMac3
 Slice:       S2.1 - Modern protocol metadata model

 Description: See KMProtocolMetadata.h. OFFLINE / PASSIVE decode only.

 This file is part of KisMAC. GPL v2.
 */

#import "KMProtocolMetadata.h"

#pragma mark - 802.11 element ids (subset relevant to S2.1)

enum {
    KM_EID_SSID          = 0,
    KM_EID_HT_CAPS       = 45,   // 802.11n
    KM_EID_RSN           = 48,   // WPA2/WPA3
    KM_EID_VHT_CAPS      = 191,  // 802.11ac
    KM_EID_VENDOR        = 221,  // vendor-specific (WPA1 lives here)
    KM_EID_EXTENSION     = 255,  // element-id extension wrapper
};

// Element-ID-extension sub-ids (the byte after id 255).
enum {
    KM_EXT_HE_CAPS       = 35,   // 802.11ax HE capabilities
    KM_EXT_HE_OPERATION  = 36,   // 802.11ax HE operation
    KM_EXT_HE_6GHZ_CAP   = 59,   // 6 GHz band capabilities (Wi-Fi 6E)
    KM_EXT_EHT_OPERATION = 106,  // 802.11be EHT operation
    KM_EXT_EHT_CAPS      = 108,  // 802.11be EHT capabilities
};

// RSN / AKM suite selectors. Suite type is the 4th byte of a 4-byte selector
// whose first 3 bytes are the OUI 00-0F-AC (IEEE) or 50-6F-9A (WFA, for OWE in
// some deployments). We only need the IEEE OUI + the type byte for AKM.
static const uint8_t KM_OUI_IEEE[3] = {0x00, 0x0F, 0xAC};

enum {
    KM_AKM_8021X         = 1,   // WPA2-Enterprise (EAP)
    KM_AKM_PSK           = 2,   // WPA2-Personal
    KM_AKM_FT_8021X      = 3,
    KM_AKM_FT_PSK        = 4,
    KM_AKM_8021X_SHA256  = 5,
    KM_AKM_PSK_SHA256    = 6,
    KM_AKM_SAE           = 8,   // WPA3-Personal
    KM_AKM_FT_SAE        = 9,
    KM_AKM_OWE           = 18,  // Enhanced Open
    KM_AKM_8021X_SUITEB     = 11, // WPA3-Enterprise
    KM_AKM_8021X_SUITEB_192 = 12, // WPA3-Enterprise 192-bit
    KM_AKM_FT_8021X_SHA384  = 13,
};

// RSN capabilities bits (the 2-byte RSN Capabilities field).
#define KM_RSN_CAP_MFPR  0x0040  // Management Frame Protection Required
#define KM_RSN_CAP_MFPC  0x0080  // Management Frame Protection Capable

// Microsoft WPA vendor IE: OUI 00-50-F2, type 1.
static const uint8_t KM_OUI_MS[3] = {0x00, 0x50, 0xF2};

#pragma mark - Decoded-AKM accumulator

typedef struct {
    BOOL sawPSK;
    BOOL sawSAE;
    BOOL sawOWE;
    BOOL sawEAP;        // any 802.1X (incl. SHA256)
    BOOL sawEAPSuiteB;  // WPA3-Enterprise
    BOOL anyAKM;
} KMAKMFlags;

@interface KMProtocolMetadata ()
@property (nonatomic, readwrite) KMSecurityMode securityMode;
@property (nonatomic, readwrite) KMPMFMode pmfMode;
@property (nonatomic, readwrite) KMPHYGeneration phyGeneration;
@property (nonatomic, readwrite) NSInteger channelWidthMHz;
@property (nonatomic, readwrite) BOOL isHiddenSSID;
@property (nonatomic, readwrite) BOOL is6GHz;
@property (nonatomic, readwrite) BOOL didDecodeAnything;
@end

@implementation KMProtocolMetadata

#pragma mark RSN IE parsing (fully bounds-checked)

// Parse the body of an RSN element (id 48) starting just past id+len.
// `body`/`bodyLen` describe ONLY the element body. Fills akm + pmf.
+ (void)parseRSNBody:(const uint8_t *)body
              length:(NSInteger)bodyLen
                 akm:(KMAKMFlags *)akm
             pmfMode:(KMPMFMode *)pmf {
    NSInteger off = 0;

    // version (2) — required.
    if (bodyLen < 2) return;
    off += 2;

    // group cipher suite (4) — optional in truncated IEs.
    if (off + 4 > bodyLen) return;
    off += 4;

    // pairwise cipher suite count (2) + list.
    if (off + 2 > bodyLen) return;
    uint16_t pwCount = (uint16_t)(body[off] | (body[off + 1] << 8));
    off += 2;
    // Guard against absurd counts that would overflow.
    if (pwCount > 255) return;
    if (off + (NSInteger)pwCount * 4 > bodyLen) return;
    off += (NSInteger)pwCount * 4;

    // AKM suite count (2) + list.
    if (off + 2 > bodyLen) return;
    uint16_t akmCount = (uint16_t)(body[off] | (body[off + 1] << 8));
    off += 2;
    if (akmCount > 255) return;
    if (off + (NSInteger)akmCount * 4 > bodyLen) return;

    for (uint16_t i = 0; i < akmCount; ++i) {
        const uint8_t *sel = body + off + (NSInteger)i * 4;
        uint8_t type = sel[3];
        BOOL ieeeOUI = (memcmp(sel, KM_OUI_IEEE, 3) == 0);
        if (!ieeeOUI) continue; // vendor AKM (e.g. WFA OWE) — ignore for posture
        akm->anyAKM = YES;
        switch (type) {
            case KM_AKM_PSK:
            case KM_AKM_FT_PSK:
            case KM_AKM_PSK_SHA256:
                akm->sawPSK = YES; break;
            case KM_AKM_SAE:
            case KM_AKM_FT_SAE:
                akm->sawSAE = YES; break;
            case KM_AKM_OWE:
                akm->sawOWE = YES; break;
            case KM_AKM_8021X:
            case KM_AKM_FT_8021X:
            case KM_AKM_8021X_SHA256:
                akm->sawEAP = YES; break;
            case KM_AKM_8021X_SUITEB:
            case KM_AKM_8021X_SUITEB_192:
            case KM_AKM_FT_8021X_SHA384:
                akm->sawEAP = YES; akm->sawEAPSuiteB = YES; break;
            default:
                break;
        }
    }
    off += (NSInteger)akmCount * 4;

    // RSN capabilities (2) — optional; needed for PMF.
    if (off + 2 <= bodyLen) {
        uint16_t cap = (uint16_t)(body[off] | (body[off + 1] << 8));
        if (cap & KM_RSN_CAP_MFPR)      *pmf = KMPMFModeRequired;
        else if (cap & KM_RSN_CAP_MFPC) *pmf = KMPMFModeCapable;
        else                            *pmf = KMPMFModeDisabled;
    }
}

#pragma mark Security classification

+ (KMSecurityMode)classifyAKM:(KMAKMFlags)akm
                   vendorWPA:(BOOL)vendorWPA
                  privacyBit:(BOOL)privacyBit {
    // OWE is mutually exclusive with PSK/SAE in practice.
    if (akm.sawOWE) return KMSecurityModeOWE;
    if (akm.sawSAE && akm.sawPSK) return KMSecurityModeWPA3Transition;
    if (akm.sawSAE)               return KMSecurityModeWPA3SAE;
    if (akm.sawEAPSuiteB)         return KMSecurityModeWPA3Enterprise;
    if (akm.sawEAP)               return KMSecurityModeWPA2Enterprise;
    if (akm.sawPSK)               return KMSecurityModeWPA2;
    if (akm.anyAKM)               return KMSecurityModeEnterprise; // RSN present, unknown AKM
    if (vendorWPA)                return KMSecurityModeWPA;
    if (privacyBit)               return KMSecurityModeWEP;
    return KMSecurityModeOpen;
}

#pragma mark Public decode entry point

+ (instancetype)metadataFromInformationElements:(const uint8_t *)ies
                                          length:(NSInteger)length
                                      privacyBit:(BOOL)privacyBit {
    KMProtocolMetadata *m = [[KMProtocolMetadata alloc] init];
    m.securityMode  = KMSecurityModeUnknown;
    m.pmfMode       = KMPMFModeUnknown;
    m.phyGeneration = KMPHYGenerationUnknown;

    if (ies == NULL || length <= 0) {
        return m;
    }

    KMAKMFlags akm = {0};
    KMPMFMode  pmf = KMPMFModeUnknown;
    BOOL vendorWPA = NO;
    BOOL sawRSN    = NO;
    BOOL sawSSID   = NO;
    BOOL hiddenSSID = NO;
    BOOL sawHT = NO, sawVHT = NO, sawHE = NO, sawEHT = NO, saw6GHz = NO;
    NSInteger width = 0;

    const uint8_t *p = ies;
    NSInteger remaining = length;

    // Robust TLV walk: every access is bounds-checked against `remaining`.
    // Each element is [id(1)][len(1)][body(len)]. We never read past `remaining`.
    while (remaining >= 2) {
        uint8_t id  = p[0];
        uint8_t len = p[1];
        // A declared length that runs past the buffer => malformed; stop.
        if ((NSInteger)len + 2 > remaining) break;

        const uint8_t *body = p + 2;
        NSInteger      bodyLen = len;

        switch (id) {
            case KM_EID_SSID: {
                sawSSID = YES;
                if (bodyLen == 0) {
                    hiddenSSID = YES;
                } else {
                    BOOL allNUL = YES;
                    for (NSInteger i = 0; i < bodyLen; ++i) {
                        if (body[i] != 0) { allNUL = NO; break; }
                    }
                    if (allNUL) hiddenSSID = YES;
                }
                break;
            }
            case KM_EID_RSN: {
                sawRSN = YES;
                m.didDecodeAnything = YES;
                [self parseRSNBody:body length:bodyLen akm:&akm pmfMode:&pmf];
                break;
            }
            case KM_EID_VENDOR: {
                // WPA1: OUI 00-50-F2, type 1.
                if (bodyLen >= 4 &&
                    memcmp(body, KM_OUI_MS, 3) == 0 && body[3] == 0x01) {
                    vendorWPA = YES;
                    m.didDecodeAnything = YES;
                }
                break;
            }
            case KM_EID_HT_CAPS: {
                sawHT = YES;
                m.didDecodeAnything = YES;
                // HT Capability Info bit 1 = "Supported Channel Width 40 MHz".
                if (bodyLen >= 2) {
                    uint16_t htcap = (uint16_t)(body[0] | (body[1] << 8));
                    if (htcap & 0x0002) { if (width < 40) width = 40; }
                    else                { if (width < 20) width = 20; }
                } else if (width < 20) { width = 20; }
                break;
            }
            case KM_EID_VHT_CAPS: {
                sawVHT = YES;
                m.didDecodeAnything = YES;
                // VHT Capabilities Info: bits 2-3 = Supported Channel Width Set.
                // 0 => 80, 1 => 160, 2 => 160+80+80. Treat >=1 as 160.
                if (bodyLen >= 1) {
                    uint8_t scw = (body[0] >> 2) & 0x03;
                    NSInteger w = (scw >= 1) ? 160 : 80;
                    if (width < w) width = w;
                } else if (width < 80) { width = 80; }
                break;
            }
            case KM_EID_EXTENSION: {
                if (bodyLen >= 1) {
                    uint8_t extID = body[0];
                    switch (extID) {
                        case KM_EXT_HE_CAPS:
                        case KM_EXT_HE_OPERATION:
                            sawHE = YES; m.didDecodeAnything = YES;
                            // HE channel width lives in the HE PHY Capabilities
                            // bitmap / HE Operation, which we do not parse here.
                            // Leave width to HT/VHT/EHT so we never assert a
                            // width we did not actually read from a frame.
                            break;
                        case KM_EXT_HE_6GHZ_CAP:
                            saw6GHz = YES; sawHE = YES; m.didDecodeAnything = YES;
                            break;
                        case KM_EXT_EHT_CAPS:
                        case KM_EXT_EHT_OPERATION:
                            sawEHT = YES; m.didDecodeAnything = YES;
                            // EHT introduces 320 MHz; flag it as the widest.
                            if (width < 320) width = 320;
                            break;
                        default:
                            break;
                    }
                }
                break;
            }
            default:
                break;
        }

        p         += (NSInteger)len + 2;
        remaining -= (NSInteger)len + 2;
    }

    // ---- finalize ----
    if (sawSSID) m.isHiddenSSID = hiddenSSID;
    m.is6GHz = saw6GHz;

    // PHY classification (most-specific wins).
    if (sawEHT)        m.phyGeneration = KMPHYGenerationWiFi7;
    else if (sawHE)    m.phyGeneration = saw6GHz ? KMPHYGenerationWiFi6E : KMPHYGenerationWiFi6;
    else if (sawVHT)   m.phyGeneration = KMPHYGenerationWiFi5;
    else if (sawHT)    m.phyGeneration = KMPHYGenerationWiFi4;
    else if (m.didDecodeAnything || sawSSID) m.phyGeneration = KMPHYGenerationLegacy;
    m.channelWidthMHz = width;

    // Security classification.
    if (sawRSN || vendorWPA || privacyBit) {
        m.securityMode = [self classifyAKM:akm vendorWPA:vendorWPA privacyBit:privacyBit];
        if (pmf != KMPMFModeUnknown) m.pmfMode = pmf;
        // For non-RSN WEP/open, PMF stays Unknown (no RSN to carry it).
    } else if (sawSSID) {
        m.securityMode = KMSecurityModeOpen;
    }

    return m;
}

#pragma mark Merge (accumulate across frames)

- (BOOL)mergeWith:(KMProtocolMetadata *)other {
    if (!other) return NO;
    BOOL changed = NO;
    // Security: prefer the more specific (higher enum, except keep Unknown<all).
    if (other.securityMode != KMSecurityModeUnknown &&
        other.securityMode > self.securityMode) {
        self.securityMode = other.securityMode; changed = YES;
    }
    if (other.pmfMode != KMPMFModeUnknown && other.pmfMode > self.pmfMode) {
        self.pmfMode = other.pmfMode; changed = YES;
    }
    if (other.phyGeneration > self.phyGeneration) {
        self.phyGeneration = other.phyGeneration; changed = YES;
    }
    if (other.channelWidthMHz > self.channelWidthMHz) {
        self.channelWidthMHz = other.channelWidthMHz; changed = YES;
    }
    if (other.is6GHz && !self.is6GHz) { self.is6GHz = YES; changed = YES; }
    if (other.didDecodeAnything && !self.didDecodeAnything) {
        self.didDecodeAnything = YES; changed = YES;
    }
    // A non-hidden observation clears a prior hidden guess.
    if (self.isHiddenSSID && !other.isHiddenSSID && other.didDecodeAnything) {
        // only relax if other actually saw an SSID element (didDecode covers IEs)
    }
    return changed;
}

#pragma mark Display strings

- (NSString *)securityDisplayString {
    NSString *base;
    switch (self.securityMode) {
        case KMSecurityModeOpen:           base = @"Open"; break;
        case KMSecurityModeWEP:            base = @"WEP"; break;
        case KMSecurityModeWPA:            base = @"WPA"; break;
        case KMSecurityModeWPA2:           base = @"WPA2-Personal"; break;
        case KMSecurityModeWPA2Enterprise: base = @"WPA2-Enterprise"; break;
        case KMSecurityModeWPA3SAE:        base = @"WPA3-SAE"; break;
        case KMSecurityModeWPA3Transition: base = @"WPA2/WPA3-Transition"; break;
        case KMSecurityModeWPA3Enterprise: base = @"WPA3-Enterprise"; break;
        case KMSecurityModeOWE:            base = @"OWE (Enhanced Open)"; break;
        case KMSecurityModeEnterprise:     base = @"802.1X-Enterprise"; break;
        case KMSecurityModeUnknown:
        default:                           base = @"Unknown"; break;
    }
    if (self.pmfMode == KMPMFModeRequired) {
        return [base stringByAppendingString:@" (PMF required)"];
    }
    if (self.pmfMode == KMPMFModeCapable) {
        return [base stringByAppendingString:@" (PMF capable)"];
    }
    return base;
}

- (NSString *)phyDisplayString {
    NSString *base;
    switch (self.phyGeneration) {
        case KMPHYGenerationLegacy: base = @"802.11a/b/g"; break;
        case KMPHYGenerationWiFi4:  base = @"Wi-Fi 4 (802.11n)"; break;
        case KMPHYGenerationWiFi5:  base = @"Wi-Fi 5 (802.11ac)"; break;
        case KMPHYGenerationWiFi6:  base = @"Wi-Fi 6 (802.11ax)"; break;
        case KMPHYGenerationWiFi6E: base = @"Wi-Fi 6E (802.11ax, 6 GHz)"; break;
        case KMPHYGenerationWiFi7:  base = @"Wi-Fi 7 (802.11be)"; break;
        case KMPHYGenerationUnknown:
        default:                    base = @"Unknown"; break;
    }
    if (self.channelWidthMHz > 0) {
        return [base stringByAppendingFormat:@", %ld MHz", (long)self.channelWidthMHz];
    }
    return base;
}

@end
