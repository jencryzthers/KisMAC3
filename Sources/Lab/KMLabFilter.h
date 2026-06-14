/*
 File:        KMLabFilter.h
 Program:     KisMac3
 Slice:       S7.1 - Authorized-lab workflow core (Milestone 10)

 Description: Client / SSID ALLOW-DENY filters for the recon + event views
              (Milestone 10 "Client and SSID allow/deny filters"). This is PURE
              DATA + matching logic -- it decides whether a given client MAC or
              SSID should be SHOWN; it has no effect on any active operation and
              does NOT widen scope. (Authorization is owned by KMCampaignScope;
              this is a view/recon filter, deliberately separate.)

              Semantics (fail-OPEN for display, NOT for authorization):
                - If an allow-list is non-empty, ONLY allow-listed values pass.
                - A deny-list value never passes (deny overrides allow).
                - Empty allow-list + empty deny-list  => everything passes.
              MAC matching is normalized (case-insensitive, separators ignored);
              SSID matching is exact (case-sensitive, as SSIDs are).

 SAFETY: this is a presentation filter. It can never authorize an active op and
         never appears in the KMLabWorkflow gate. Keeping it out of the gate is
         intentional: a permissive view filter must not be mistakable for scope.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KMLabFilter : NSObject <NSCopying>

/// Allow-listed client MACs. Empty => no client allow restriction.
@property (nonatomic, copy) NSSet<NSString *> *allowClientMACs;
/// Deny-listed client MACs (overrides allow).
@property (nonatomic, copy) NSSet<NSString *> *denyClientMACs;
/// Allow-listed SSIDs. Empty => no SSID allow restriction.
@property (nonatomic, copy) NSSet<NSString *> *allowSSIDs;
/// Deny-listed SSIDs (overrides allow).
@property (nonatomic, copy) NSSet<NSString *> *denySSIDs;

/// An empty filter (everything passes).
+ (instancetype)emptyFilter;

#pragma mark Matching (deny overrides allow; empty allow-list = allow all)

/// YES iff the client MAC should be shown given the client allow/deny lists.
- (BOOL)allowsClientMAC:(nullable NSString *)mac;
/// YES iff the SSID should be shown given the SSID allow/deny lists.
- (BOOL)allowsSSID:(nullable NSString *)ssid;

/// Convenience: YES iff BOTH the client and the SSID pass (nil = unconstrained
/// on that axis). Used to filter a recon row that has a client AND an SSID.
- (BOOL)allowsClientMAC:(nullable NSString *)mac ssid:(nullable NSString *)ssid;

@end

NS_ASSUME_NONNULL_END
