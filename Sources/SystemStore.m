#import "Language.h"
#import "SystemStore.h"
#import "BackupRetention.h"
#import <sqlite3.h>
#import <dlfcn.h>

// Undocumented KeyboardServices selectors, checked at runtime before use.
// All system writes go through the service. SQLite is opened READONLY only.
@protocol PhraseEntry <NSObject>
@property(copy) NSString *shortcut;
@property(copy) NSString *phrase;
@end
@protocol PhraseService <NSObject>
- (void)addEntries:(NSArray *)add removeEntries:(NSArray *)remove withCompletionHandler:(void (^)(NSError *))completion;
- (void)modifyEntry:(id)original toEntry:(id)replacement withCompletionHandler:(void (^)(NSError *))completion;
@end

static NSError *Failure(NSString *message) {
    return [NSError errorWithDomain:@"SystemPhraseBar" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}

@implementation SystemStore {
    id<PhraseService> _service;
    Class _entryClass;
    NSURL *_databaseURL;
    BOOL _busy;
}
- (instancetype)init {
    if ((self = [super init])) {
        dlopen("/System/Library/PrivateFrameworks/KeyboardServices.framework/KeyboardServices", RTLD_LAZY | RTLD_LOCAL);
        Class storeClass = NSClassFromString(@"_KSTextReplacementClientStore");
        _entryClass = NSClassFromString(@"_KSTextReplacementEntry");
        if ([storeClass instancesRespondToSelector:@selector(addEntries:removeEntries:withCompletionHandler:)] &&
            [storeClass instancesRespondToSelector:@selector(modifyEntry:toEntry:withCompletionHandler:)] &&
            [_entryClass instancesRespondToSelector:@selector(setShortcut:)] &&
            [_entryClass instancesRespondToSelector:@selector(setPhrase:)]) {
            _service = (id<PhraseService>)[storeClass new];
        }
        _databaseURL = [[NSFileManager defaultManager].homeDirectoryForCurrentUser URLByAppendingPathComponent:@"Library/KeyboardServices/TextReplacements.db"];
    }
    return self;
}
- (BOOL)available { return _service != nil; }

- (NSArray<NSDictionary *> *)readEntries:(NSError **)error {
    sqlite3 *db = NULL;
    if (sqlite3_open_v2(_databaseURL.fileSystemRepresentation, &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
        if (error) *error = Failure(L(@"Could not read your phrases. Open System Settings → Keyboard → Text Replacements, then refresh."));
        if (db) sqlite3_close(db);
        return nil;
    }
    sqlite3_busy_timeout(db, 2000);
    const char *sql = "SELECT Z_PK,ZSHORTCUT,ZPHRASE,ZTIMESTAMP FROM ZTEXTREPLACEMENTENTRY WHERE COALESCE(ZWASDELETED,0)=0 ORDER BY ZSHORTCUT,ZPHRASE";
    sqlite3_stmt *statement = NULL;
    NSMutableArray *entries = [NSMutableArray array];
    int rc = sqlite3_prepare_v2(db, sql, -1, &statement, NULL);
    if (rc == SQLITE_OK) {
        while ((rc = sqlite3_step(statement)) == SQLITE_ROW) {
            const char *shortcut = (const char *)sqlite3_column_text(statement, 1);
            const char *phrase = (const char *)sqlite3_column_text(statement, 2);
            // Preserve entries with no shortcut: macOS can keep phrase-only entries.
            if (!phrase || ![NSString stringWithUTF8String:phrase] || (shortcut && ![NSString stringWithUTF8String:shortcut])) {
                rc = SQLITE_MISMATCH;
                break;
            }
            [entries addObject:@{@"id":@(sqlite3_column_int64(statement,0)),
                @"shortcut":shortcut ? [NSString stringWithUTF8String:shortcut] : @"",
                @"phrase":[NSString stringWithUTF8String:phrase],
                @"timestamp":@(sqlite3_column_double(statement,3))}];
        }
    }
    sqlite3_finalize(statement);
    sqlite3_close(db);
    if (rc != SQLITE_DONE) {
        if (error) *error = Failure(L(@"The system phrase data could not be read. No changes were made."));
        return nil;
    }
    return entries;
}

- (id<PhraseEntry>)serviceEntry:(NSDictionary *)entry {
    id<PhraseEntry> value = (id<PhraseEntry>)[_entryClass new];
    value.shortcut = entry[@"shortcut"];
    value.phrase = entry[@"phrase"];
    return value;
}
- (BOOL)contains:(NSDictionary *)entry in:(NSArray *)entries {
    for (NSDictionary *item in entries) {
        if ([item[@"shortcut"] isEqual:entry[@"shortcut"]] && [item[@"phrase"] isEqual:entry[@"phrase"]]) return YES;
    }
    return NO;
}
- (BOOL)backup:(NSArray *)entries error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *directory=BackupDirectory();
    if (![fm createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil]) {
        if(error) *error=Failure(L(@"Could not save a backup. No changes were made.")); return NO;
    }
    // Make room before creating the next backup: a cleanup failure cannot grow the folder.
    if(!PruneBackups(directory,BackupLimit-1,nil)) {
        if(error) *error=Failure(L(@"Could not clean up old backups. No changes were made.")); return NO;
    }
    NSMutableArray *export = [NSMutableArray array];
    for (NSDictionary *entry in entries) [export addObject:@{@"shortcut":entry[@"shortcut"],@"phrase":entry[@"phrase"]}];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:export format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
    if (!data) return NO;
    NSURL *url = [directory URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", NSUUID.UUID.UUIDString]];
    // Unique names and 0600 keep the logical backup private.
    return [fm createFileAtPath:url.path contents:data attributes:@{NSFilePosixPermissions:@0600}] ? YES : ({ if(error) *error=Failure(L(@"Could not save a backup. No changes were made.")); NO; });
}

- (void)saveShortcut:(NSString *)shortcut phrase:(NSString *)phrase original:(NSDictionary *)original completion:(void (^)(NSError *))completion {
    [self change:@{@"shortcut":shortcut,@"phrase":phrase} original:original completion:completion];
}
- (void)deleteEntry:(NSDictionary *)entry completion:(void (^)(NSError *))completion {
    [self change:nil original:entry completion:completion];
}
- (void)change:(NSDictionary *)next original:(NSDictionary *)original completion:(void (^)(NSError *))completion {
    NSAssert(NSThread.isMainThread, @"Mutations are serialized on main thread");
    if (_busy) { completion(Failure(L(@"Another change is still in progress. Please wait."))); return; }
    if (!_service) { completion(Failure(L(@"This macOS version is not compatible with the phrase service. Use System Settings instead."))); return; }
    if (next && (!next[@"phrase"] || [next[@"phrase"] length]==0 ||
        [next[@"shortcut"] rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location!=NSNotFound ||
        [next[@"shortcut"] rangeOfCharacterFromSet:[NSCharacterSet characterSetWithRange:NSMakeRange(0,1)]].location!=NSNotFound ||
        [next[@"phrase"] rangeOfCharacterFromSet:[NSCharacterSet characterSetWithRange:NSMakeRange(0,1)]].location!=NSNotFound)) {
        completion(Failure(L(@"Enter a phrase. Shortcuts cannot contain spaces or line breaks."))); return;
    }
    NSError *error=nil;
    NSArray *current=[self readEntries:&error];
    if (!current) { completion(error); return; }
    if (original) {
        // An entry changed through Settings/iCloud must not be silently overwritten.
        BOOL exact=NO;
        for (NSDictionary *entry in current) if ([entry isEqual:original]) exact=YES;
        if (!exact) { completion(Failure(L(@"This phrase changed in System Settings or on another device. Refresh before editing again."))); return; }
    }
    if (next) {
        for (NSDictionary *entry in current) {
            if (![entry isEqual:original] && (([next[@"shortcut"] length] && [entry[@"shortcut"] isEqual:next[@"shortcut"]]) ||
                ([entry[@"shortcut"] isEqual:next[@"shortcut"]] && [entry[@"phrase"] isEqual:next[@"phrase"]]))) {
                completion(Failure(L(@"That shortcut or phrase already exists. Edit the existing entry instead."))); return;
            }
        }
        if (original && [original[@"shortcut"] isEqual:next[@"shortcut"]] && [original[@"phrase"] isEqual:next[@"phrase"]]) { completion(nil); return; }
    }
    if (![self backup:current error:&error]) { completion(error); return; }
    _busy=YES;
    __block BOOL delivered=NO;
    void (^finish)(NSError *)=^(NSError *failure) {
        if(delivered) return;
        delivered=YES;
        self->_busy=NO;
        completion(failure);
    };
    void (^reply)(NSError *)=^(NSError *serviceError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (delivered) return;
            if (serviceError && serviceError.code!=0) { finish(Failure([NSString stringWithFormat:L(@"macOS could not save the change (%@ %ld)."),serviceError.domain,(long)serviceError.code])); return; }
            // A successful callback alone is insufficient; verify the durable store.
            [self verify:next original:original attempt:0 finish:finish];
        });
    };
    if (next && original) [_service modifyEntry:[self serviceEntry:original] toEntry:[self serviceEntry:next] withCompletionHandler:reply];
    else [_service addEntries:next ? @[[self serviceEntry:next]] : @[] removeEntries:original ? @[[self serviceEntry:original]] : @[] withCompletionHandler:reply];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,12*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        finish(Failure(L(@"macOS did not confirm the change in time. Refresh or check System Settings before trying again.")));
    });
}
- (void)verify:(NSDictionary *)next original:(NSDictionary *)original attempt:(NSUInteger)attempt finish:(void (^)(NSError *))finish {
    NSError *error=nil;
    NSArray *entries=[self readEntries:&error];
    BOOL present=entries && (!next || [self contains:next in:entries]);
    BOOL removed=entries && (!original || ![self contains:original in:entries]);
    if(present && removed) { finish(nil); return; }
    if(attempt>=9) { finish(error ?: Failure(L(@"The saved change could not be verified. Refresh to check it; the app will not retry automatically."))); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        [self verify:next original:original attempt:attempt+1 finish:finish];
    });
}
@end
