/*

 File:          KMPcapImportSelfTest.h
 Program:       KisMAC

 Description:   S2.2 — headless, env-gated self-test that proves the OFFLINE
                pcap/pcapng import path (-[WaveScanner readPCAPDump:]) works
                without the GUI and without any live-capture capability.
                It imports a committed golden fixture into a throwaway
                WaveContainer and asserts the resulting network/client counts
                match the fixture's known-good values.

                OFFLINE / PASSIVE ONLY. This never starts a scan, never touches
                a radio, never enters monitor mode, never switches channels.

 This file is part of KisMAC.

 KisMAC is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License, version 2,
 as published by the Free Software Foundation;
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KMPcapImportSelfTest : NSObject

/// Imports the pcap at `path` into a throwaway container via the offline
/// pipeline and writes the resulting network / client counts to the out params.
/// Returns NO if the file could not be opened / imported.
+ (BOOL)importFixtureAtPath:(NSString *)path
                networkCount:(NSUInteger *)outNetworks
                 clientCount:(NSUInteger *)outClients;

/// Runs the self-test against the fixture named by the KISMAC_PCAP_IMPORT_SELFTEST
/// environment variable, or the committed golden fixture when that value is "1"
/// or empty. Logs a single PASS/FAIL line (with actual vs expected counts) via
/// DBNSLog. Returns YES on PASS.
+ (BOOL)runSelfTestLogging;

@end

NS_ASSUME_NONNULL_END
