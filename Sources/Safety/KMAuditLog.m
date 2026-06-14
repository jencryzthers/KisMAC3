/*
 File:        KMAuditLog.m
 Program:     KisMac3
 Slice:       S4.1 - Campaign scope + audit log + emergency stop

 This file is part of KisMAC. GPL v2.
 */

#import "KMAuditLog.h"
#import "KMRedactionSettings.h"

#ifndef DBNSLog
#define DBNSLog NSLog
#endif

NSString * const KMAuditActionCampaignArmed    = @"campaign_armed";
NSString * const KMAuditActionCampaignDisarmed  = @"campaign_disarmed";
NSString * const KMAuditActionScopeChanged      = @"scope_changed";
NSString * const KMAuditActionEmergencyStop     = @"emergency_stop";
NSString * const KMAuditActionActiveOperation   = @"active_operation";
NSString * const KMAuditActionSelfTest          = @"self_test";

@interface KMAuditLog ()
@property (nonatomic, copy) NSURL *directory;
@property (nonatomic, strong) NSDateFormatter *dayFormatter;
@property (nonatomic, strong) NSDateFormatter *isoFormatter;
@property (nonatomic, strong) dispatch_queue_t ioQueue;
@end

@implementation KMAuditLog

+ (instancetype)sharedLog {
    static KMAuditLog *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *appSup = [[NSFileManager defaultManager]
            URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask
            appropriateForURL:nil create:YES error:NULL];
        NSURL *dir = [appSup URLByAppendingPathComponent:@"KisMac3" isDirectory:YES];
        shared = [[self alloc] initWithDirectory:dir];
    });
    return shared;
}

- (instancetype)initWithDirectory:(NSURL *)directory {
    if ((self = [super init])) {
        _directory = [directory copy];
        _ioQueue = dispatch_queue_create("com.kismac.audit", DISPATCH_QUEUE_SERIAL);

        _dayFormatter = [[NSDateFormatter alloc] init];
        _dayFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        _dayFormatter.dateFormat = @"yyyy-MM-dd";

        _isoFormatter = [[NSDateFormatter alloc] init];
        _isoFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        _isoFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZ";

        [[NSFileManager defaultManager] createDirectoryAtURL:_directory
                                 withIntermediateDirectories:YES
                                                  attributes:nil error:NULL];
    }
    return self;
}

- (NSURL *)currentLogFileURL {
    NSString *day = [self.dayFormatter stringFromDate:[NSDate date]];
    NSString *name = [NSString stringWithFormat:@"audit-%@.jsonl", day];
    return [self.directory URLByAppendingPathComponent:name];
}

#pragma mark Redaction of an entry's identifier fields

/// Applies redaction to the human `detail` line and any string values inside
/// the context dictionary. Audit metadata (action/timestamp) is never touched.
- (id)redactedValue:(id)value {
    KMRedactionSettings *r = self.redaction;
    if (!r || !r.enabled) return value;
    if ([value isKindOfClass:[NSString class]]) {
        return [r redactString:(NSString *)value];
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
            out[k] = [self redactedValue:v];
        }];
        return out;
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray array];
        for (id v in (NSArray *)value) [out addObject:[self redactedValue:v]];
        return out;
    }
    return value;
}

#pragma mark Append (never silently drops)

- (BOOL)appendAction:(NSString *)action
              detail:(NSString *)detail
             context:(NSDictionary<NSString *, id> *)context {
    NSDate *now = [NSDate date];

    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"ts"] = [self.isoFormatter stringFromDate:now];
    entry[@"action"] = action ?: @"unknown";
    entry[@"detail"] = [self redactedValue:(detail ?: @"")];
    if (context.count) {
        entry[@"context"] = [self redactedValue:context];
    }

    __block BOOL ok = NO;
    dispatch_sync(self.ioQueue, ^{
        NSError *err = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:entry
                                                       options:0 error:&err];
        if (!json) {
            // Last-ditch: a JSON-safe fallback so we still RECORD something.
            NSString *fallback = [NSString stringWithFormat:
                @"{\"ts\":\"%@\",\"action\":\"%@\",\"detail\":\"<unencodable>\"}",
                entry[@"ts"], entry[@"action"]];
            json = [fallback dataUsingEncoding:NSUTF8StringEncoding];
            DBNSLog(@"[KMAuditLog] entry not JSON-encodable (%@); wrote fallback line.", err);
        }
        NSMutableData *line = [json mutableCopy];
        [line appendBytes:"\n" length:1];

        NSURL *url = [self currentLogFileURL];
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:url.path]) {
            ok = [line writeToURL:url options:NSDataWritingAtomic error:&err];
            if (!ok) DBNSLog(@"[KMAuditLog] FAILED to create audit log %@: %@", url.path, err);
        } else {
            NSFileHandle *fh = [NSFileHandle fileHandleForWritingToURL:url error:&err];
            if (fh) {
                @try {
                    [fh seekToEndOfFile];
                    [fh writeData:line];
                    [fh closeFile];
                    ok = YES;
                } @catch (NSException *ex) {
                    DBNSLog(@"[KMAuditLog] FAILED to append to %@: %@", url.path, ex);
                }
            } else {
                DBNSLog(@"[KMAuditLog] FAILED to open audit log %@ for append: %@", url.path, err);
            }
        }
    });
    return ok;
}

#pragma mark Read back

- (NSArray<NSDictionary<NSString *, id> *> *)readCurrentEntries {
    __block NSMutableArray *out = [NSMutableArray array];
    dispatch_sync(self.ioQueue, ^{
        NSString *content = [NSString stringWithContentsOfURL:[self currentLogFileURL]
                                                     encoding:NSUTF8StringEncoding error:NULL];
        if (!content) return;
        for (NSString *line in [content componentsSeparatedByString:@"\n"]) {
            if (line.length == 0) continue;
            NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
            id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
            if ([obj isKindOfClass:[NSDictionary class]]) [out addObject:obj];
        }
    });
    return [out copy];
}

@end
