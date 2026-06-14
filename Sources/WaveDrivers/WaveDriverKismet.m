/*
 
 File:			WaveDriverKismet.m
 Program:		KisMAC
 Author:		Geordie Millar
                themacuser@gmail.com
 Changes:       Vitalii Parovishnyk(1012-2015)
 
 Description:	Scan with a Kismet server in KisMac.
 
 Details:		Tested with Kismet 2006.04.R1 on OpenWRT White Russian RC6 on a Diamond Digital R100
                (broadcom mini-PCI card, wrt54g capturesource)
                and Kismet 2006.04.R1 on Voyage Linux on a PC Engines WRAP.2E
                (CM9 mini-PCI card, madwifing)
 
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

#import "WaveDriverKismet.h"
#import "WaveHelper.h"
#import "KMKismetTransport.h"
#import <Cocoa/Cocoa.h>
#include "80211b.h"

static NSInteger KismetInstances = 0;

// S2.4: surface a connection failure as a modern NSAlert instead of the
// deprecated NSRunCriticalAlertPanel, and ALWAYS log it (no silent failure).
static void KMKismetShowError(NSString *title, NSString *detail) {
    DBNSLog(@"[Kismet] %@: %@", title, detail);
    dispatch_block_t showBlock = ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleCritical;
        alert.messageText = title;
        alert.informativeText = detail;
        [alert addButtonWithTitle:NSLocalizedString(@"OK", "")];
        [alert runModal];
    };
    if ([NSThread isMainThread]) showBlock();
    else dispatch_async(dispatch_get_main_queue(), showBlock);
}

@implementation WaveDriverKismet

- (id)init {
    self = [super init];
    if (!self)  return nil;
    
    ++KismetInstances;

    return self;
}

+(NSInteger) kismetInstanceCount {
    return KismetInstances;
}

#pragma mark -

+ (enum WaveDriverType) type {
    return activeDriver;
}

+ (BOOL) wantsIPAndPort {
    return YES;
}

+ (NSString*) description {
    return NSLocalizedString(@"Kismet Server, Passive Mode", "long driver description");
}

+ (NSString*) deviceName {
    return NSLocalizedString(@"Kismet Server", "short driver description");
}

#pragma mark -

+ (BOOL) loadBackend {
    return YES;
}

+ (BOOL) unloadBackend {
    return YES;
}

#pragma mark -

- (BOOL) startedScanning {
	NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];

	// The legacy *NETWORK: text protocol's subscribe command. Plaintext.
	const char *initstr = "!0 ENABLE NETWORK bssid,type,wep,signal,maxrate,channel,ssid\n";

	BOOL foundhostname = NO;
	BOOL foundport = NO;

	NSArray *a = [defs objectForKey:@"ActiveDrivers"];
	for (NSDictionary *drvr in a) {
		@try {
			if ([drvr[@"driverID"] isEqualToString:@"WaveDriverKismet"]) {
				hostname = [drvr[@"kismetserverhost"] copy];
				if (hostname.length) foundhostname = YES;
				port = [drvr[@"kismetserverport"] intValue];
				if (port > 0) foundport = YES;
			}
		}
		@catch (NSException * ex) {
			DBNSLog(@"Exception getting the hostname and port from plist...");
		}
	}

	if (!foundhostname || !foundport) {
		KMKismetShowError(NSLocalizedString(@"No host/port set to connect to!", "Error dialog title"),
		                  NSLocalizedString(@"Check that a Kismet server host and port are set in the preferences.", "LONG desc"));
		return NO;
	}

	// S2.4: Network.framework transport (plaintext TCP). Replaces the raw
	// socket()/connect()/blocking read(); supports IPv4 + IPv6 (was inet_addr
	// IPv4-only); a refused/unreachable/timed-out connect surfaces a clear
	// reason rather than hanging or producing nothing.
	_transport = [[KMKismetTransport alloc] initWithHost:hostname port:(uint16_t)port];
	if (![_transport connectWithTimeout:10.0]) {
		KMKismetShowError(NSLocalizedString(@"Could not connect to the Kismet server", "Error dialog title"),
		                  [NSString stringWithFormat:
		                   NSLocalizedString(@"KisMac could not connect to the Kismet server at %@ port %ld. %@", "LONG desc"),
		                   hostname, (long)port, [_transport lastErrorReason]]);
		[_transport close];
		_transport = nil;
		return NO;
	}

	if (![_transport sendBytes:initstr length:strlen(initstr)]) {
		KMKismetShowError(NSLocalizedString(@"Could not connect to the Kismet server", "Error dialog title"),
		                  NSLocalizedString(@"Failed to send the protocol subscription command.", "LONG desc"));
		[_transport close];
		_transport = nil;
		return NO;
	}

	return YES;
}

- (BOOL) stopCapture {
	[_transport close];
	_transport = nil;
	return YES;
}

#pragma mark -

- (NSArray*) networksInRange {
	NSInteger len,i,j,flags,t,signalint;
	NSInteger usenetarray = 0;
	char netbuf[2048];
	NSUInteger bssidbyte;
	char bssidstring[6];
	NSString *netrcvd, *name;
	NSArray *netarray,*rcvd,*rcvd2,*rcvd3,*bssidar;
	NSDictionary *nets;
	NSData *bssid;
	NSNumber *signal,*noise,*channel,*capability,*isWPA;
		
	// S2.4: pull from the Network.framework transport instead of a blocking
	// read(). A short timeout keeps the scan loop responsive; 0 bytes simply
	// means "nothing this poll" (return nil, loop again). -1 means the
	// connection failed/closed -> surface it and stop, never hang silently.
	len = [_transport readUpTo:(sizeof(netbuf) - 1) into:netbuf timeout:1.0];
	if (len < 0) {
		KMKismetShowError(NSLocalizedString(@"Lost connection to the Kismet server", "Error dialog title"),
		                  [_transport lastErrorReason]);
		return nil;
	}
	if (len == 0) {
		return nil; // no data this poll; not an error
	}

	netarray = @[];
    //NULL terminate
    netbuf[len] = 0;
	netrcvd = @(netbuf);
	rcvd2 = [netrcvd componentsSeparatedByString:@"\n"]; // split packet into lines
	NSInteger arrayCount = [rcvd2 count];
	for (i = 0; i < arrayCount; ++i) { // iterate through each line - 1 line = 1 network
		@try {
				netrcvd = rcvd2[i]; // put the current object into netrcvd
				rcvd = [netrcvd componentsSeparatedByString:@"\x01"]; // strip the SSID out
				rcvd3 = [rcvd[0] componentsSeparatedByString:@" "]; // strip the rest down
				if ([rcvd3[0] isEqualToString:@"*NETWORK:"]) { // if this is a line specifying a new network
					bssidar = [rcvd3[1] componentsSeparatedByString:@":"]; // get the BSSID
					
					for (j = 0; j < 6; ++j) {
						sscanf([bssidar[j] UTF8String], "%lx", &bssidbyte); // convert it from ascii 12:34:56 into raw binary
						bssidstring[j] = bssidbyte;
					}
					
					bssid = [NSData dataWithBytes:bssidstring length:6];					// bssid, simple enough
					signalint = [rcvd3[4] intValue];							// signal level, as an NSInteger
					if (signalint > 1000 || signalint < 0) { signalint = 0; }				// sometimes it comes through as an invalid number
					signal = @(signalint);							// signal level as NSNumber, you can't put NSInteger into array
					noise = @0;										// this is only subtracted from signal, not needed
					channel = @([rcvd3[6] intValue]);	// channel...
					
					flags = 0;
					
					if ([rcvd3[3] intValue] == 2) {
						flags = flags | IEEE80211_CAPINFO_PRIVACY_LE; // if it's 2, it's WEP
					}
					
					if ([rcvd3[3] intValue] > 2) { // it's either not WEP, or it's some other encryption scheme
						isWPA = @1; // it's WPA
					} else {
						isWPA = @0; // it's open, or we don't know what it is
					}
					
					t = [rcvd3[2] intValue]; // network type
					
					if (t == 0) {
					flags = flags | IEEE80211_CAPINFO_ESS_LE;		// it's managed
					} else if (t == 1) {
					flags = flags | IEEE80211_CAPINFO_IBSS_LE;		// it's adhoc
					} else if (t == 2) {
					flags = flags | IEEE80211_CAPINFO_PROBE_REQ_LE; // it's a probe request
					}
					capability = @(flags);
					name = rcvd[1];
					nets = @{@"BSSID": bssid,@"signal": signal,@"noise": noise,@"channel": channel,@"isWPA": isWPA,@"name": name,@"capability": capability};
					netarray = [netarray arrayByAddingObject:nets];
					usenetarray = 1; // we do want to send the result
				}
		}
		@catch (NSException *exception) {
			DBNSLog(@"Invalid message, ignored"); // if an invalid message came in, ignore it instead of crashing
		}
	}
	if (usenetarray == 1) { return netarray; } else { return nil; } // return the result
}

#pragma mark -

- (void) hopToNextChannel {
	return;
}

#pragma mark -

-(void) dealloc {
    KismetInstances--;
    [_transport close];
    _transport = nil;
}

@end
