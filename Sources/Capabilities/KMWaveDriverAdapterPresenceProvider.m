/*
 File:        KMWaveDriverAdapterPresenceProvider.m
 Program:     KisMac3
 Slice:       S4.2 - Gate inject/deauth/AP behind capability + scope

 This file is part of KisMAC. GPL v2.
 */

#import "KMWaveDriverAdapterPresenceProvider.h"
#import "../Core/WaveHelper.h"
#import "../WaveDrivers/WaveDriver.h"

@implementation KMWaveDriverAdapterPresenceProvider

- (BOOL)hasInjectionCapableAdapter {
    // FAIL CLOSED: any loaded driver that advertises injection capability means
    // an external transmit-capable adapter is present. The built-in card's
    // driver returns +allowsInjection = NO, so on a stock MacBook this is NO.
    NSArray *drivers = [WaveHelper getWaveDrivers];
    for (WaveDriver *w in drivers) {
        if ([w respondsToSelector:@selector(allowsInjection)] && [w allowsInjection]) {
            return YES;
        }
    }
    return NO;
}

@end
