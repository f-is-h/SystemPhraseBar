#import "BackupRetention.h"
#import "Language.h"

NSUInteger const BackupLimit=20;
NSURL *BackupDirectory(void) {
    return [NSFileManager.defaultManager.homeDirectoryForCurrentUser URLByAppendingPathComponent:@"Library/Application Support/SystemPhraseBar/Backups" isDirectory:YES];
}
BOOL PruneBackups(NSURL *directory, NSUInteger keep, NSError **error) {
    NSFileManager *fm=NSFileManager.defaultManager;
    BOOL isDirectory=NO;
    if(![fm fileExistsAtPath:directory.path isDirectory:&isDirectory]) return YES;
    if(!isDirectory) {
        if(error) *error=[NSError errorWithDomain:@"SystemPhraseBar.Backups" code:1 userInfo:@{NSLocalizedDescriptionKey:L(@"The backup location is not a folder.")}];
        return NO;
    }
    NSArray *urls=[fm contentsOfDirectoryAtURL:directory includingPropertiesForKeys:@[NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey,NSURLContentModificationDateKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:error];
    if(!urls) return NO;
    NSMutableArray *owned=[NSMutableArray array];
    for(NSURL *url in urls) {
        // App backups use UUID.plist. Leave symlinks, directories and user files alone.
        if(![url.pathExtension isEqual:@"plist"] || ![[NSUUID alloc] initWithUUIDString:url.lastPathComponent.stringByDeletingPathExtension]) continue;
        NSDictionary *values=[url resourceValuesForKeys:@[NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey,NSURLContentModificationDateKey] error:error];
        if(!values) return NO;
        if(![values[NSURLIsRegularFileKey] boolValue] || [values[NSURLIsSymbolicLinkKey] boolValue]) continue;
        NSData *data=[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
        if(!data) return NO;
        id plist=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil];
        BOOL valid=[plist isKindOfClass:NSArray.class];
        if(valid) for(id entry in plist) {
            if(![entry isKindOfClass:NSDictionary.class] || [entry count]!=2 ||
               ![entry[@"shortcut"] isKindOfClass:NSString.class] || ![entry[@"phrase"] isKindOfClass:NSString.class]) { valid=NO; break; }
        }
        if(valid) [owned addObject:@{@"url":url,@"date":values[NSURLContentModificationDateKey] ?: NSDate.distantPast}];
    }
    [owned sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult order=[b[@"date"] compare:a[@"date"]];
        return order==NSOrderedSame ? [[a[@"url"] lastPathComponent] compare:[b[@"url"] lastPathComponent]] : order;
    }];
    for(NSUInteger index=keep;index<owned.count;index++) if(![fm removeItemAtURL:owned[index][@"url"] error:error]) return NO;
    return YES;
}
