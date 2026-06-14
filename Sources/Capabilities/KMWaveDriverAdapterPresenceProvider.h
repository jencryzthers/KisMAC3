/*
 File:        KMWaveDriverAdapterPresenceProvider.h
 Program:     KisMac3
 Slice:       S4.2 - Gate inject/deauth/AP behind capability + scope

 Description: The REAL <KMAdapterPresenceProviding> for the capability engine.
              Reports YES iff at least one loaded WaveDriver advertises
              injection/transmit capability (i.e. a WaveDriverUSB-class external
              adapter whose +allowsInjection is YES). The built-in MacBook Wi-Fi
              card's driver reports +allowsInjection = NO, so on a MacBook with
              no external adapter this provider correctly reports NO and the
              engine gates the offensive trio with unsupportedAdapter.

              FAIL CLOSED: if the driver list cannot be obtained, reports NO.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>
#import "KMCapabilityEngine.h"   // <KMAdapterPresenceProviding>

NS_ASSUME_NONNULL_BEGIN

/// Backed by -[WaveHelper getWaveDrivers] / -[WaveDriver allowsInjection].
@interface KMWaveDriverAdapterPresenceProvider : NSObject <KMAdapterPresenceProviding>
- (BOOL)hasInjectionCapableAdapter;
@end

NS_ASSUME_NONNULL_END
