/*
 File:        KMKismetTransport.m
 Program:     KisMac3
 Slice:       S2.4 - Kismet remote/drone backend modernization

 Description: See KMKismetTransport.h. Plaintext TCP over Network.framework.

 This file is part of KisMAC. GPL v2.
 */

#import "KMKismetTransport.h"
#import <Network/Network.h>

@interface KMKismetTransport ()
@property (nonatomic, copy)   NSString *host;
@property (nonatomic, assign) uint16_t  port;
@property (atomic, assign)    BOOL       isConnected;
@property (atomic, assign)    BOOL       isFailed;
@property (atomic, strong, nullable) NSError *lastError;
@end

@implementation KMKismetTransport {
    nw_connection_t   _connection;        // strong via ARC bridging below
    dispatch_queue_t  _queue;             // serial queue for nw callbacks
    dispatch_semaphore_t _dataReady;      // signalled when bytes arrive / state changes

    NSMutableData    *_buffer;            // received-but-undrained bytes
    NSLock           *_bufferLock;        // guards _buffer
    BOOL              _receiving;         // a receive is currently outstanding
    BOOL              _eof;               // server closed cleanly
}

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port {
    if ((self = [super init])) {
        _host = [host copy];
        _port = port;
        _queue = dispatch_queue_create("org.kismac.kismet.transport", DISPATCH_QUEUE_SERIAL);
        _dataReady = dispatch_semaphore_create(0);
        _buffer = [NSMutableData data];
        _bufferLock = [[NSLock alloc] init];
    }
    return self;
}

- (void)dealloc {
    [self close];
}

#pragma mark - Connect

- (BOOL)connectWithTimeout:(NSTimeInterval)timeout {
    if (_host.length == 0) {
        self.lastError = [NSError errorWithDomain:@"KMKismetTransport" code:EINVAL
                                         userInfo:@{NSLocalizedDescriptionKey: @"No Kismet host configured."}];
        self.isFailed = YES;
        return NO;
    }

    // Plaintext TCP. NO TLS: legacy Kismet is plaintext by design (documented).
    nw_parameters_t params = nw_parameters_create_secure_tcp(
        NW_PARAMETERS_DISABLE_PROTOCOL,   // no TLS
        NW_PARAMETERS_DEFAULT_CONFIGURATION);

    char portStr[8];
    snprintf(portStr, sizeof(portStr), "%u", (unsigned)_port);
    // nw_endpoint_create_host resolves names AND accepts IPv4/IPv6 literals,
    // replacing the IPv4-only inet_addr() the legacy drivers used.
    nw_endpoint_t endpoint = nw_endpoint_create_host([_host UTF8String], portStr);

    nw_connection_t conn = nw_connection_create(endpoint, params);
    if (!conn) {
        self.lastError = [NSError errorWithDomain:@"KMKismetTransport" code:ENOMEM
                                         userInfo:@{NSLocalizedDescriptionKey: @"Could not create the network connection."}];
        self.isFailed = YES;
        return NO;
    }

    _connection = conn;
    nw_connection_set_queue(conn, _queue);

    __weak KMKismetTransport *weakSelf = self;
    dispatch_semaphore_t ready = dispatch_semaphore_create(0);

    nw_connection_set_state_changed_handler(conn, ^(nw_connection_state_t state, nw_error_t error) {
        KMKismetTransport *strongSelf = weakSelf;
        if (!strongSelf) return;
        switch (state) {
            case nw_connection_state_ready:
                strongSelf.isConnected = YES;
                dispatch_semaphore_signal(ready);
                [strongSelf startReceive];
                break;
            case nw_connection_state_failed:
            case nw_connection_state_cancelled: {
                if (error) {
                    int ec = nw_error_get_error_code(error);
                    strongSelf.lastError = [NSError errorWithDomain:@"KMKismetTransport.nw"
                        code:ec userInfo:@{NSLocalizedDescriptionKey:
                            [NSString stringWithFormat:@"Network error %d (%s)", ec, strerror(ec)]}];
                }
                strongSelf.isFailed = YES;
                strongSelf.isConnected = NO;
                dispatch_semaphore_signal(ready);          // unblock connect()
                dispatch_semaphore_signal(strongSelf->_dataReady); // unblock read()
                break;
            }
            default:
                break;
        }
    });

    nw_connection_start(conn);

    dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));
    long waited = dispatch_semaphore_wait(ready, deadline);
    if (waited != 0) {
        // Timed out establishing the connection -> NOT a silent failure.
        self.lastError = [NSError errorWithDomain:@"KMKismetTransport" code:ETIMEDOUT
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Timed out connecting to %@:%u after %.0f s.",
                    _host, (unsigned)_port, timeout]}];
        self.isFailed = YES;
        nw_connection_cancel(conn);
        return NO;
    }

    return self.isConnected && !self.isFailed;
}

#pragma mark - Receive pump

- (void)startReceive {
    if (!_connection || self.isFailed) return;
    @synchronized (self) {
        if (_receiving || _eof) return;
        _receiving = YES;
    }
    nw_connection_t conn = _connection;
    __weak KMKismetTransport *weakSelf = self;
    nw_connection_receive(conn, 1, 65536,
        ^(dispatch_data_t content, nw_content_context_t context, bool is_complete, nw_error_t error) {
        KMKismetTransport *strongSelf = weakSelf;
        if (!strongSelf) return;

        if (content) {
            dispatch_data_apply(content, ^bool(dispatch_data_t region, size_t offset, const void *buf, size_t size) {
                [strongSelf->_bufferLock lock];
                [strongSelf->_buffer appendBytes:buf length:size];
                [strongSelf->_bufferLock unlock];
                return true;
            });
            dispatch_semaphore_signal(strongSelf->_dataReady);
        }

        @synchronized (strongSelf) { strongSelf->_receiving = NO; }

        if (error) {
            int ec = nw_error_get_error_code(error);
            strongSelf.lastError = [NSError errorWithDomain:@"KMKismetTransport.nw"
                code:ec userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Receive error %d (%s)", ec, strerror(ec)]}];
            strongSelf.isFailed = YES;
            dispatch_semaphore_signal(strongSelf->_dataReady);
            return;
        }

        if (is_complete) {
            // Server closed the stream cleanly.
            @synchronized (strongSelf) { strongSelf->_eof = YES; }
            dispatch_semaphore_signal(strongSelf->_dataReady);
            return;
        }

        // Keep pumping.
        [strongSelf startReceive];
    });
}

#pragma mark - Read (pull model, bounded)

- (NSInteger)readUpTo:(NSUInteger)maxLength into:(void *)dst timeout:(NSTimeInterval)timeout {
    if (maxLength == 0 || dst == NULL) return 0;

    dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));

    for (;;) {
        // Drain whatever is buffered.
        [_bufferLock lock];
        NSUInteger avail = _buffer.length;
        if (avail > 0) {
            NSUInteger n = MIN(avail, maxLength);
            memcpy(dst, _buffer.bytes, n);
            [_buffer replaceBytesInRange:NSMakeRange(0, n) withBytes:NULL length:0];
            [_bufferLock unlock];
            return (NSInteger)n;
        }
        [_bufferLock unlock];

        // No data: a failed/closed connection means "stop", not "hang".
        if (self.isFailed) return -1;
        @synchronized (self) { if (_eof) return -1; }

        // Wait for the next chunk or the deadline.
        long waited = dispatch_semaphore_wait(_dataReady, deadline);
        if (waited != 0) {
            // Timed out with no data. Not an error -- caller polls again.
            return 0;
        }
        // Re-check state and loop to drain.
        if (self.isFailed) {
            // Could still have buffered bytes that arrived alongside the error.
            [_bufferLock lock];
            NSUInteger a = _buffer.length;
            [_bufferLock unlock];
            if (a == 0) return -1;
        }
    }
}

#pragma mark - Send

- (BOOL)sendBytes:(const void *)bytes length:(NSUInteger)length {
    return [self sendData:[NSData dataWithBytes:bytes length:length]];
}

- (BOOL)sendData:(NSData *)data {
    if (!_connection || self.isFailed || !self.isConnected) return NO;
    dispatch_data_t dd = dispatch_data_create(data.bytes, data.length, _queue,
                                              DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    __weak KMKismetTransport *weakSelf = self;
    nw_connection_send(_connection, dd, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true,
        ^(nw_error_t error) {
        if (error) {
            KMKismetTransport *strongSelf = weakSelf;
            if (!strongSelf) return;
            int ec = nw_error_get_error_code(error);
            strongSelf.lastError = [NSError errorWithDomain:@"KMKismetTransport.nw"
                code:ec userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Send error %d (%s)", ec, strerror(ec)]}];
            strongSelf.isFailed = YES;
            dispatch_semaphore_signal(strongSelf->_dataReady);
        }
    });
    return YES;
}

#pragma mark - Teardown

- (void)close {
    nw_connection_t conn = _connection;
    _connection = nil;
    if (conn) {
        nw_connection_cancel(conn);
    }
    self.isConnected = NO;
    // Wake any blocked reader so the driver loop can exit.
    if (_dataReady) dispatch_semaphore_signal(_dataReady);
}

- (NSString *)lastErrorReason {
    NSError *e = self.lastError;
    if (e.localizedDescription.length) return e.localizedDescription;
    return @"Unknown network error.";
}

@end
