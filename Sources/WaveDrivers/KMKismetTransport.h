/*
 File:        KMKismetTransport.h
 Program:     KisMac3
 Slice:       S2.4 - Kismet remote/drone backend modernization

 Description: A modern, non-blocking TCP transport for the legacy Kismet
              remote/drone backends, built on Network.framework (NWConnection),
              replacing the raw BSD socket()/connect()/blocking read() calls in
              WaveDriverKismet.m and WaveDriverKismetDrone.m.

              The legacy drivers use a PULL model: the scan loop repeatedly calls
              -networksInRange (text backend) or -nextFrame (drone backend), and
              expects to read whatever bytes have arrived. NWConnection is push /
              callback driven, so this class bridges the two: it receives bytes
              on an internal serial queue into a thread-safe buffer, and the
              driver drains that buffer synchronously via -readUpTo:into:.

              NO SILENT FAILURE: connection setup is synchronous-with-timeout
              (-connectWithTimeout:) and returns NO with a populated -lastError on
              refused / unreachable / timed-out connections. Once connected, a
              dropped connection sets -failed = YES and surfaces -lastError; the
              driver checks -isFailed and stops the capture loop instead of
              hanging or silently producing nothing.

              TRANSPORT IS PLAINTEXT TCP by design: legacy Kismet (2006-era
              *NETWORK: text protocol and the binary drone stream) is plaintext.
              We do NOT wrap this in TLS -- doing so would not talk to a legacy
              server. This is documented and intentional; a modern Kismet 3.x
              (REST/websocket/JSON over TLS) adapter is a SEPARATE future slice
              that needs a live server to validate.

              ENTITLEMENT NOTE: com.apple.security.network.client is only required
              under the App Sandbox. This app is currently UNSANDBOXED, so no
              entitlement change is made here. If/when sandboxing lands (S8.x),
              that entitlement must be added for outbound Kismet connections.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KMKismetTransport : NSObject

/// The host this transport connects to (hostname or IPv4/IPv6 literal).
@property (nonatomic, copy, readonly) NSString *host;
/// The TCP port.
@property (nonatomic, assign, readonly) uint16_t port;

/// YES once -connectWithTimeout: has reported a ready connection.
@property (atomic, assign, readonly) BOOL isConnected;
/// YES if the connection failed to establish OR dropped after being ready.
/// The driver's pull loop checks this to stop cleanly instead of hanging.
@property (atomic, assign, readonly) BOOL isFailed;
/// The last error encountered (connect failure, drop, etc.), or nil.
@property (atomic, strong, readonly, nullable) NSError *lastError;

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Resolves + connects with a bounded timeout (seconds). Blocks the CALLING
/// thread (the driver's background scan thread) until ready/failed/timeout.
/// Returns YES iff the connection became ready. On failure, -lastError is set
/// and a human-readable reason is available via -lastErrorReason. Supports both
/// IPv4 and IPv6 (Network.framework resolves names; the legacy inet_addr path
/// was IPv4-only).
- (BOOL)connectWithTimeout:(NSTimeInterval)timeout;

/// Sends raw bytes to the server (e.g. the Kismet ENABLE command or the drone
/// FLUSH command). Returns NO if not connected / failed.
- (BOOL)sendBytes:(const void *)bytes length:(NSUInteger)length;
- (BOOL)sendData:(NSData *)data;

/// Drains up to maxLength buffered bytes into dst, blocking up to timeout
/// seconds for at least one byte to arrive. Returns the number of bytes copied
/// (0 on timeout-with-no-data; this is NOT an error). Returns -1 if the
/// connection has failed/closed (caller should stop). Mirrors the semantics the
/// legacy blocking read() gave the drivers, but never hangs forever and never
/// fails silently.
- (NSInteger)readUpTo:(NSUInteger)maxLength into:(void *)dst timeout:(NSTimeInterval)timeout;

/// Closes the connection and tears down the queue. Idempotent.
- (void)close;

/// A short human-readable description of -lastError for alerts/logs.
- (NSString *)lastErrorReason;

@end

NS_ASSUME_NONNULL_END
