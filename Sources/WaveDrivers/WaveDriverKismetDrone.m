/*
 
 File:			WaveDriverKismetDrone.m
 Program:		KisMAC
 Author:		Geordie Millar
                themacuser@gmail.com
 Changes:       Vitalii Parovishnyk(1012-2015)
 
 Description:	Scan with a Kismet drone (as opposed to kismet server) in KisMac.
 
 Details:		Tested with kismet_drone 2006.04.R1 on OpenWRT White Russian RC6 on a Diamond Digital R100
                (broadcom mini-PCI card, wrt54g capturesource)
                and kismet_drone 2006.04.R1 on Voyage Linux on a PC Engines WRAP.2E
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

#import "WaveDriverKismetDrone.h"
#import "ImportController.h"
#import "WaveHelper.h"
#import "KMKismetTransport.h"
#import <Cocoa/Cocoa.h>
#import <BIGeneric/BIGeneric.h>

// S2.4: modern, always-logged error surface (replaces NSRunCriticalAlertPanel).
static void KMDroneShowError(NSString *title, NSString *detail) {
    DBNSLog(@"[KismetDrone] %@: %@", title, detail);
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

@implementation WaveDriverKismetDrone

// Reads EXACTLY `need` bytes into dst[*recv ..], updating *recv, blocking up to
// `timeout` per poll. Returns YES once *recv >= need; NO if the connection
// failed/closed (caller surfaces + bails). Replaces the drone's blocking read()
// loops with the Network.framework transport. The original code also had a bug
// where a short/zero read could leave the protocol parser spinning; here a
// closed connection is an explicit NO.
- (BOOL)fillBuffer:(uint8_t *)dst received:(NSUInteger *)recv need:(NSUInteger)need
{
    while (*recv < need) {
        NSInteger n = [_transport readUpTo:(need - *recv) into:(dst + *recv) timeout:2.0];
        if (n < 0) return NO;       // connection failed / closed
        if (n == 0) {               // no data this poll
            if (_transport.isFailed) return NO;
            continue;               // keep waiting (bounded by stopCapture/close)
        }
        *recv += (NSUInteger)n;
    }
    return YES;
}

+ (enum WaveDriverType) type
{
    return passiveDriver;
}

+ (BOOL) allowsInjection
{
    return NO;
}

+ (BOOL) wantsIPAndPort
{
    return YES;
}

+ (BOOL) allowsChannelHopping
{
    return NO;
}

+ (NSString*) description
{
    return NSLocalizedString(@"Kismet Drone (raw packets), passive mode", "long driver description");
}

+ (NSString*) deviceName
{
    return NSLocalizedString(@"Kismet Drone", "short driver description");
}

#pragma mark -


+ (BOOL)deviceAvailable
{
	return YES;
}


+ (NSInteger) initBackend
{
	return YES;
}

+ (BOOL) loadBackend
{
	return YES;
}

+ (BOOL) unloadBackend
{
	return YES;
}

#pragma mark -

- (id)init
{
    self = [super init];
    if (!self)  return nil;
    
	return self;
}

#pragma mark -

- (UInt16) getChannelUnCached
{
	return _currentChannel;
}

- (BOOL) setChannel:(UInt16)newChannel
{
	_currentChannel = newChannel;
	return YES;
}

- (BOOL) startCapture:(UInt16)newChannel
{
    return YES;
}

- (BOOL) stopCapture
{
	[_transport close];
	_transport = nil;
    return YES;
}

#pragma mark -

- (BOOL)startedScanning
{
	NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
	NSString *hostname = nil;
	NSUInteger port = 0;

	BOOL foundhostname = NO;
	BOOL foundport = NO;

	NSArray *activeDrivers = [defs objectForKey:@"ActiveDrivers"];

	// NOTE (fixed bug): the original wrapped the whole loop in @try and, on ANY
	// exception, reported "No host/port set" -- masking real causes. Reading a
	// plist value can't throw here, so the @try was removed; missing values are
	// handled explicitly below.
	for (NSDictionary *drvr in activeDrivers) {
		if ([drvr[@"driverID"] isEqualToString:@"WaveDriverKismetDrone"]) {
			hostname = [drvr[@"kismetserverhost"] copy];
			if (hostname.length) foundhostname = YES;
			port = [drvr[@"kismetserverport"] intValue];
			if (port > 0) foundport = YES;
		}
	}

	if (!foundhostname || !foundport) {
		KMDroneShowError(NSLocalizedString(@"No host/port set to connect to!", "Error dialog title"),
		                 NSLocalizedString(@"Check that a Kismet drone host and port are set in the preferences.", "LONG desc"));
		return NO;
	}

	// S2.4 BUG FIX: the original set drone_sock.sin_addr.s_addr = ip BEFORE
	// memset(&drone_sock, 0, ...), so the just-set address was immediately
	// zeroed (connect would target 0.0.0.0). It also used inet_addr (IPv4-only)
	// and a needless bind() to INADDR_ANY:0 before connect. All of that is gone:
	// KMKismetTransport (Network.framework) resolves IPv4 + IPv6 and connects
	// with a bounded timeout, surfacing refused/unreachable/timeout clearly
	// instead of hanging or silently failing. Plaintext TCP (drone stream is
	// plaintext).
	_transport = [[KMKismetTransport alloc] initWithHost:hostname port:(uint16_t)port];
	if (![_transport connectWithTimeout:10.0]) {
		KMDroneShowError(NSLocalizedString(@"The connection to the Kismet drone failed", "Error dialog title"),
		                 [NSString stringWithFormat:
		                  NSLocalizedString(@"KisMac could not connect to the Kismet drone at %@ port %lu. %@", "LONG desc"),
		                  hostname, (unsigned long)port, [_transport lastErrorReason]]);
		[_transport close];
		_transport = nil;
		return NO;
	}

	valid = 1;
	resyncs = 0;
	resyncing = 0;
	stream_recv_bytes = 0;

	return YES;
}

#pragma mark -

- (KFrame*) nextFrame
{
	// S2.4: rewritten onto the Network.framework transport. The binary drone
	// stream (~2006 STREAM_DRONE_VERSION 9) protocol semantics are preserved --
	// per frame: read the frame header, validate the sentinel (FLUSH-resync on
	// mismatch), then read the version packet OR the packet header + payload per
	// frame_type. All length/version/oversize validation is kept. The legacy
	// blocking read()/select()/fd_set/errno BSD calls are gone; -fillBuffer:
	// reads exactly N bytes from the transport and returns NO when the
	// connection failed/closed so we bail cleanly instead of hanging or
	// silently producing nothing.
	static UInt8 frame[2500];
	KFrame *thisFrame = (KFrame*)frame;

	if (!_transport || _transport.isFailed) {
		return NULL; // connection gone -> stop the capture loop
	}

	while (1)
	{
		// ---- 1. Frame header ----
		NSUInteger got = 0;
		if (![self fillBuffer:(uint8_t *)&fhdr received:&got need:sizeof(struct stream_frame_header)]) {
			KMDroneShowError(NSLocalizedString(@"The connection to the Kismet drone failed", "Error dialog title"),
			                 [NSString stringWithFormat:NSLocalizedString(@"Error reading the frame header. %@", ""),
			                  [_transport lastErrorReason]]);
			return NULL;
		}

		// Validate the sentinel; on mismatch, request a FLUSH resync.
		if (ntohl(fhdr.frame_sentinel) != STREAM_SENTINEL) {
			++resyncs;
			if (resyncs > 20) {
				KMDroneShowError(NSLocalizedString(@"The connection to the Kismet drone failed", "Error dialog title"),
				                 NSLocalizedString(@"Resync attempted too many times; the stream is out of sync.", ""));
				return NULL;
			}
			int8_t cmd = STREAM_COMMAND_FLUSH;
			if (![_transport sendBytes:&cmd length:1]) {
				KMDroneShowError(NSLocalizedString(@"The connection to the Kismet drone failed", "Error dialog title"),
				                 NSLocalizedString(@"Write error flushing the packet stream.", ""));
				return NULL;
			}
			continue; // re-read a fresh frame header
		}
		resyncs = 0;

		// ---- 2a. Version frame ----
		if (fhdr.frame_type == STREAM_FTYPE_VERSION) {
			NSUInteger vgot = 0;
			if (![self fillBuffer:(uint8_t *)&vpkt received:&vgot need:sizeof(struct stream_version_packet)]) {
				KMDroneShowError(NSLocalizedString(@"The connection to the Kismet drone failed", "Error dialog title"),
				                 NSLocalizedString(@"Read error getting the version packet.", ""));
				return NULL;
			}
			if (ntohs(vpkt.drone_version) != STREAM_DRONE_VERSION) {
				KMDroneShowError(NSLocalizedString(@"The connection to the Kismet drone failed", "Error dialog title"),
				                 [NSString stringWithFormat:NSLocalizedString(@"Version mismatch: drone sent %d, expected %d.", ""),
				                  ntohs(vpkt.drone_version), STREAM_DRONE_VERSION]);
				return NULL;
			}
			DBNSLog(@"[KismetDrone] version packet valid (v%d)", STREAM_DRONE_VERSION);
			continue; // wait for the next (packet) frame
		}

		// ---- 2b. Packet frame ----
		if (fhdr.frame_type == STREAM_FTYPE_PACKET) {
			if (ntohl(fhdr.frame_len) <= sizeof(struct stream_packet_header)) {
				KMDroneShowError(NSLocalizedString(@"The connection to the Kismet drone failed", "Error dialog title"),
				                 NSLocalizedString(@"Frame too small to hold a packet.", ""));
				return NULL;
			}

			NSUInteger pgot = 0;
			if (![self fillBuffer:(uint8_t *)&phdr received:&pgot need:sizeof(struct stream_packet_header)]) {
				KMDroneShowError(NSLocalizedString(@"The connection to the Kismet drone failed", "Error dialog title"),
				                 NSLocalizedString(@"Read error getting the packet header.", ""));
				return NULL;
			}

			if (ntohs(phdr.drone_version) != STREAM_DRONE_VERSION) {
				KMDroneShowError(NSLocalizedString(@"The connection to the Kismet drone failed", "Error dialog title"),
				                 [NSString stringWithFormat:NSLocalizedString(@"Version mismatch: drone sent %d, expected %d.", ""),
				                  ntohs(phdr.drone_version), STREAM_DRONE_VERSION]);
				return NULL;
			}
			if (ntohl(phdr.caplen) <= 0 || ntohl(phdr.len) <= 0) {
				KMDroneShowError(NSLocalizedString(@"The connection to the Kismet drone failed", "Error dialog title"),
				                 NSLocalizedString(@"Drone sent a zero-length packet.", ""));
				return NULL;
			}
			if (ntohl(phdr.caplen) > MAX_PACKET_LEN || ntohl(phdr.len) > MAX_PACKET_LEN) {
				KMDroneShowError(NSLocalizedString(@"The connection to the Kismet drone failed", "Error dialog title"),
				                 NSLocalizedString(@"Drone sent an oversized packet.", ""));
				return NULL;
			}

			// ---- 3. Payload ----
			NSUInteger plen = (uint32_t) ntohl(phdr.len);
			if (plen > sizeof(databuf)) plen = sizeof(databuf); // clamp: no overflow
			NSUInteger dgot = 0;
			if (![self fillBuffer:databuf received:&dgot need:plen]) {
				KMDroneShowError(NSLocalizedString(@"The connection to the Kismet drone failed", "Error dialog title"),
				                 NSLocalizedString(@"Read error getting the packet payload.", ""));
				return NULL;
			}

			thisFrame->ctrl.len     = (UInt16) ntohl(phdr.caplen);
			thisFrame->ctrl.signal  = (UInt8)  ntohs(phdr.signal);
			thisFrame->ctrl.channel = (UInt16) phdr.channel;
			thisFrame->ctrl.rate    = (UInt8)  ntohl(phdr.datarate);

			if (thisFrame->ctrl.len > MAX_FRAME_BYTES) { // no buffer overflows please
				thisFrame->ctrl.len = MAX_FRAME_BYTES;
				DBNSLog(@"[KismetDrone] captured frame >%d octets, clamped", MAX_FRAME_BYTES);
			}
			if (thisFrame->ctrl.len > plen) {
				thisFrame->ctrl.len = (UInt16)plen; // never read past what arrived
			}

			memcpy(thisFrame->data, databuf, thisFrame->ctrl.len);
			stream_recv_bytes = 0;
			return thisFrame; // got one
		}

		// ---- Unknown frame type ----
		DBNSLog(@"[KismetDrone] unknown frame type %d", fhdr.frame_type);
		return NULL;
	}
}

@end
