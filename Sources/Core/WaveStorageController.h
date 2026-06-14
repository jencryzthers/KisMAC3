/*
 
 File:			WaveStorageController.h
 Program:		KisMAC
 Author:		Michael Roßberg
                mick@binaervarianz.de
 Changes:       Vitalii Parovishnyk(1012-2015)
 
 Description:	KisMAC is a wireless stumbler for MacOS X.
 
 This file is part of KisMAC.
 
 Most parts of this file are based on aircrack by Christophe Devine.
 
 KisMAC is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License, version 2,
 as published by the Free Software Foundation;
 
 KisMAC is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with KisMAC; if not, write to the Free Software
 Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

@class WaveContainer;
@class ImportController;

@interface WaveStorageController : NSObject
{
}

//functions for loading and saving etc
+ (BOOL)importFromFile:(NSString*)filename withContainer:(WaveContainer*)container andImportController:(ImportController*)im;
+ (BOOL)loadFromFile:(NSString*)filename withContainer:(WaveContainer*)container andImportController:(ImportController*)im;

+ (BOOL)importFromNetstumbler:(NSString*)filename withContainer:(WaveContainer*)container andImportController:(ImportController*)im;
+ (NSString*)webServiceDataOfContainer:(WaveContainer*)container andImportController:(ImportController*)im;

+ (BOOL)saveToFile:(NSString*)filename withContainer:(WaveContainer*)container andImportController:(ImportController*)im;

// S6.1 — secure legacy `.kismac` unarchive (exposed for the S6.1 self-test).
// Decodes an NSKeyedArchiver graph with an EXPLICIT NSSecureCoding allowlist via
// +unarchivedObjectOfClasses:fromData:error:. Returns nil (logs) on a disallowed
// class or corrupt data — never the old insecure -unarchiveObjectWithData: path.
+ (NSSet<Class> *)secureLegacyAllowedClasses;
+ (NSDictionary *)secureLegacyDictionaryFromData:(NSData *)rawData;

// S6.2 — full save-with-encryption -> open-with-passphrase round-trip self-test
// through this controller (imports golden.pcap, saves encrypted, reloads,
// asserts the network set is preserved, and that open WITHOUT / with WRONG
// passphrase fails cleanly). Returns YES iff all sub-checks pass. Logs PASS/FAIL,
// never the passphrase. Restores any prior privacy flag + session passphrase.
+ (BOOL)runProjectCryptoStorageSelfTestLogging;
+ (BOOL)exportNSToFile:(NSString*)filename withContainer:(WaveContainer*)container andImportController:(ImportController*)im;
+ (BOOL)exportKMLToFile:(NSString*)filename withContainer:(WaveContainer*)container andImportController:(ImportController*)im;
+ (BOOL)exportMacStumblerToFile:(NSString*)filename withContainer:(WaveContainer*)container andImportController:(ImportController*)im;

@end
