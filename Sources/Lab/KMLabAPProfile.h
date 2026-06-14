/*
 File:        KMLabAPProfile.h
 Program:     KisMac3
 Slice:       S7.1 - Authorized-lab workflow core (Milestone 10)

 Description: A LAB AP PROFILE: the model for an OWNED test network used in an
              authorized lab (Milestone 10 "Lab AP profiles for owned test
              networks"). It is DATA + SCOPE-BINDING only -- it is NOT an access
              point implementation and creates/transmits nothing.

              A profile becomes "usable/active" ONLY when it is within the
              current authorized campaign scope: its BSSID and SSID must both be
              in scope (-isUsableWithScopeProvider:). Out of scope (or with no
              active campaign) it is NOT usable -- fail closed.

 SAFETY: a profile is a label for a network the operator owns and has scoped.
         Marking one "usable" does not enable any radio behavior; the active
         operations remain gated by KMLabWorkflow + the S4.2 op-site gate.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

@protocol KMLabScopeChecking;

NS_ASSUME_NONNULL_BEGIN

/// Security posture label for an owned test network (descriptive only).
typedef NS_ENUM(NSInteger, KMLabAPSecurity) {
    KMLabAPSecurityOpen = 0,
    KMLabAPSecurityWEP,
    KMLabAPSecurityWPA2Personal,
    KMLabAPSecurityWPA3Personal,
    KMLabAPSecurityEnterprise,
};

extern NSString *KMStringFromLabAPSecurity(KMLabAPSecurity security);

@interface KMLabAPProfile : NSObject <NSSecureCoding, NSCopying>

/// Stable identifier (UUID string).
@property (nonatomic, copy, readonly) NSString *identifier;
/// Human-readable label.
@property (nonatomic, copy) NSString *label;
/// The owned network's SSID.
@property (nonatomic, copy) NSString *ssid;
/// The owned network's BSSID (AP MAC).
@property (nonatomic, copy) NSString *bssid;
/// Wi-Fi channel.
@property (nonatomic, assign) NSInteger channel;
/// Security posture (descriptive).
@property (nonatomic, assign) KMLabAPSecurity security;

- (instancetype)initWithLabel:(NSString *)label
                         ssid:(NSString *)ssid
                        bssid:(NSString *)bssid
                      channel:(NSInteger)channel
                     security:(KMLabAPSecurity)security NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

#pragma mark Scope binding (fail closed)

/// YES iff BOTH this profile's BSSID and SSID are within the current authorized
/// campaign scope. With no active scope (or out-of-scope) this returns NO. The
/// profile is only "usable" in the lab when this is YES.
- (BOOL)isUsableWithScopeProvider:(nullable id<KMLabScopeChecking>)scopeProvider;

/// Redaction-aware one-line description (honors KMRedactionSettings).
- (NSString *)redactedDescriptionWithSettings:(nullable id)settings;

@end

NS_ASSUME_NONNULL_END
