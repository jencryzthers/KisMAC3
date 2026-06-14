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
/// without this machine's hardware. Pass nil for scopeProvider/parserRegistry
/// to get the fail-closed default (no scope) / current-parity defaults.
- (instancetype)initWithHardwareCapabilities:(NSArray<KMHardwareCapability *> *)hardware
                               scopeProvider:(nullable id<KMActiveScopeProviding>)scopeProvider
                             parserRegistry:(nullable KMProtocolParserRegistry *)parserRegistry
    NS_DESIGNATED_INITIALIZER;

/// Convenience: build from an already-run hardware probe.
- (instancetype)initWithProbe:(KMHardwareProbe *)probe;

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
