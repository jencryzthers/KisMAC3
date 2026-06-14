/*
 File:        KMCapabilityEngine.h
 Program:     KisMac3
 Slice:       S1.3 - Capability engine core

 Description: The single source of truth for feature availability. UI and
              drivers ask the engine "is feature X available, and if not,
              why?" -- they must NEVER decide hardware support themselves.

 The engine computes availability for every Milestone 3 capability by combining
 four INJECTABLE inputs, which makes it unit-testable WITHOUT this machine's
 hardware:
   1. hardware/OS facts  -- an NSArray<KMHardwareCapability *> from S1.1
                            (the engine CONSUMES these; it never calls the
                            probe inside its decision logic).
   2. permission state   -- derived from the injected hardware facts
                            (e.g. location.authorization).
   3. active-lab scope   -- a scope provider; today a fail-closed stub that
                            reports NO active scope (S4.1 owns the real one).
   4. protocol parsers   -- a registry of which decoders exist today (none of
                            the modern ones yet; S2.1 owns them).
   5. adapter presence   -- none today, so external-module / adapter-only
                            radio ops report unsupportedAdapter.

 FAIL-CLOSED: anything not provably available is unavailable, and every active/
              offensive op stays unavailable while no campaign scope is in
              effect, regardless of hardware.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>
#import "KMCapability.h"
#import "KMHardwareCapability.h"

@class KMHardwareProbe;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Active-lab scope provider

/// Provides the current active/authorized campaign scope. S4.1 owns the real
/// implementation; until then KMNoActiveScopeProvider is used and every active/
/// offensive op fails closed.
@protocol KMActiveScopeProviding <NSObject>
/// YES iff an authorized campaign scope is currently in effect.
- (BOOL)hasActiveScope;
@end

/// Fail-closed stub: never has an active scope. (S4.1 replaces this.)
@interface KMNoActiveScopeProvider : NSObject <KMActiveScopeProviding>
@end

#pragma mark - Adapter-presence provider (S4.2)

/// Reports whether an injection/transmit-capable radio adapter is present.
/// The built-in MacBook Wi-Fi card CANNOT inject/deauth/AP (parity: built-in
/// 🚫), so the only "YES" path is an external USB adapter whose driver
/// `+allowsInjection` is YES. The engine consumes this to decide the offensive
/// trio (frameInjection/deauth/apMode) with a 3-way result:
///   no adapter            => unsupportedAdapter (built-in can't; needs external)
///   adapter + no scope     => activeLabScopeMissing
///   adapter + active scope => available
@protocol KMAdapterPresenceProviding <NSObject>
/// YES iff an injection/transmit-capable adapter is currently present.
- (BOOL)hasInjectionCapableAdapter;
@end

/// Fail-closed default: reports NO injection-capable adapter. Used when no real
/// provider is injected (e.g. unit tests / engines built before a driver is
/// known). The built-in card is never injection-capable, so NO is correct.
@interface KMNoAdapterPresenceProvider : NSObject <KMAdapterPresenceProviding>
@end

#pragma mark - Protocol parser registry

/// Registry of which protocol decoders exist today. The modern decoders are
/// NOT implemented yet (S2.1), so by default this reports them all missing.
@interface KMProtocolParserRegistry : NSObject
/// YES iff a decoder for the given feature key exists.
- (BOOL)hasParserForFeature:(NSString *)featureKey;
/// Registers a parser as present (used by S2.1 and by tests).
- (void)registerParserForFeature:(NSString *)featureKey;
/// Default registry: nothing modern registered (current parity).
+ (instancetype)defaultRegistry;
@end

#pragma mark - KMCapabilityEngine

@interface KMCapabilityEngine : NSObject

/// Designated initializer. Takes INJECTED inputs so it is fully testable
/// without this machine's hardware. Pass nil for scopeProvider/parserRegistry/
/// adapterProvider to get the fail-closed defaults (no scope / current-parity
/// parsers / NO injection-capable adapter).
- (instancetype)initWithHardwareCapabilities:(NSArray<KMHardwareCapability *> *)hardware
                               scopeProvider:(nullable id<KMActiveScopeProviding>)scopeProvider
                             parserRegistry:(nullable KMProtocolParserRegistry *)parserRegistry
                            adapterProvider:(nullable id<KMAdapterPresenceProviding>)adapterProvider
    NS_DESIGNATED_INITIALIZER;

/// Convenience: build from an already-run hardware probe.
- (instancetype)initWithProbe:(KMHardwareProbe *)probe;

/// Convenience: build from an already-run hardware probe with an INJECTED
/// scope provider (S4.1 wires the real KMActiveCampaignScopeProvider here so
/// active/offensive features are gated on an authorized in-window campaign).
/// Pass nil to get the fail-closed default (no scope).
- (instancetype)initWithProbe:(KMHardwareProbe *)probe
                scopeProvider:(nullable id<KMActiveScopeProviding>)scopeProvider;

/// Convenience (S4.2): build from a probe with INJECTED scope + adapter-presence
/// providers. The adapter provider drives the offensive trio's
/// unsupportedAdapter vs activeLabScopeMissing vs available 3-way. Pass nil for
/// either to get the fail-closed default (no scope / no adapter).
- (instancetype)initWithProbe:(KMHardwareProbe *)probe
                scopeProvider:(nullable id<KMActiveScopeProviding>)scopeProvider
              adapterProvider:(nullable id<KMAdapterPresenceProviding>)adapterProvider;

/// Convenience: run a real probe synchronously and build from it.
/// NOTE: touches real hardware -- never use this in unit tests.
- (instancetype)initWithLiveProbe;

- (instancetype)init NS_UNAVAILABLE;

#pragma mark Public API

/// The capability descriptor for a single feature key.
- (KMCapability *)availabilityForCapability:(NSString *)featureKey;

/// Convenience: YES iff -availabilityForCapability: is available.
- (BOOL)isAvailable:(NSString *)featureKey;

/// All Milestone 3 capabilities, in canonical order.
- (NSArray<KMCapability *> *)allCapabilities;

#pragma mark Self-test (mocked-input verification)

/// Builds the mocked scenarios, asserts expected state+reason for
/// representative capabilities, and returns YES if ALL pass. On failure,
/// *outFailures (if provided) is populated with human-readable failure lines.
/// This is hardware-INDEPENDENT (all inputs are mocked).
+ (BOOL)runSelfTestReturningFailures:(NSArray<NSString *> * _Nullable * _Nullable)outFailures;

/// Runs the self-test and logs PASS/FAIL with details. Returns YES on pass.
+ (BOOL)runSelfTestLogging;

@end

NS_ASSUME_NONNULL_END
