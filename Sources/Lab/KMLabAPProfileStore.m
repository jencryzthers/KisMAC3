/*
 File:        KMLabAPProfileStore.m
 Program:     KisMac3
 Slice:       S7.1 - Authorized-lab workflow core (Milestone 10)

 Description: See KMLabAPProfileStore.h. Local secure-coded persistence.

 This file is part of KisMAC. GPL v2.
 */

#import "KMLabAPProfileStore.h"

#ifndef DBNSLog
    #define DBNSLog NSLog
#endif

@interface KMLabAPProfileStore ()
@property (nonatomic, copy) NSURL *fileURL;
@property (nonatomic, strong) NSMutableArray<KMLabAPProfile *> *mutableProfiles;
@end

@implementation KMLabAPProfileStore

+ (instancetype)sharedStore {
    static KMLabAPProfileStore *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *appSup = [[NSFileManager defaultManager]
            URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask
            appropriateForURL:nil create:YES error:NULL];
        NSURL *dir = [appSup URLByAppendingPathComponent:@"KisMac3" isDirectory:YES];
        [[NSFileManager defaultManager] createDirectoryAtURL:dir
            withIntermediateDirectories:YES attributes:nil error:NULL];
        NSURL *file = [dir URLByAppendingPathComponent:@"lab-ap-profiles.plist"];
        shared = [[self alloc] initWithFileURL:file];
    });
    return shared;
}

- (instancetype)initWithFileURL:(NSURL *)fileURL {
    self = [super init];
    if (self) {
        _fileURL = [fileURL copy];
        _mutableProfiles = [NSMutableArray array];
        [self reload];
    }
    return self;
}

- (NSArray<KMLabAPProfile *> *)profiles {
    @synchronized (self) { return [self.mutableProfiles copy]; }
}

- (BOOL)reload {
    NSData *data = [NSData dataWithContentsOfURL:self.fileURL];
    if (!data) {
        @synchronized (self) { [self.mutableProfiles removeAllObjects]; }
        return YES;  // no file yet = empty store, fine
    }
    NSSet *classes = [NSSet setWithObjects:
        [NSArray class], [KMLabAPProfile class], [NSString class], [NSNumber class], nil];
    NSError *err = nil;
    id obj = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:&err];
    if (![obj isKindOfClass:[NSArray class]]) {
        DBNSLog(@"[KMLabAPProfileStore] could not decode profiles: %@", err);
        return NO;  // fail closed: keep whatever we had, don't crash
    }
    @synchronized (self) {
        [self.mutableProfiles removeAllObjects];
        for (id p in (NSArray *)obj) {
            if ([p isKindOfClass:[KMLabAPProfile class]]) [self.mutableProfiles addObject:p];
        }
    }
    return YES;
}

- (BOOL)persist {
    NSArray<KMLabAPProfile *> *snapshot = self.profiles;
    NSError *err = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:snapshot
                                        requiringSecureCoding:YES error:&err];
    if (!data) {
        DBNSLog(@"[KMLabAPProfileStore] could not encode profiles: %@", err);
        return NO;
    }
    BOOL ok = [data writeToURL:self.fileURL atomically:YES];
    if (!ok) DBNSLog(@"[KMLabAPProfileStore] could not write %@", self.fileURL);
    return ok;
}

- (BOOL)addProfile:(KMLabAPProfile *)profile {
    if (![profile isKindOfClass:[KMLabAPProfile class]]) return NO;
    @synchronized (self) {
        NSUInteger existing = NSNotFound;
        for (NSUInteger i = 0; i < self.mutableProfiles.count; i++) {
            if ([self.mutableProfiles[i].identifier isEqualToString:profile.identifier]) {
                existing = i; break;
            }
        }
        if (existing != NSNotFound) self.mutableProfiles[existing] = profile;
        else [self.mutableProfiles addObject:profile];
    }
    return [self persist];
}

- (BOOL)removeProfileWithIdentifier:(NSString *)identifier {
    @synchronized (self) {
        NSMutableArray *kept = [NSMutableArray array];
        for (KMLabAPProfile *p in self.mutableProfiles) {
            if (![p.identifier isEqualToString:identifier]) [kept addObject:p];
        }
        self.mutableProfiles = kept;
    }
    return [self persist];
}

- (BOOL)removeAllProfiles {
    @synchronized (self) { [self.mutableProfiles removeAllObjects]; }
    return [self persist];
}

@end
