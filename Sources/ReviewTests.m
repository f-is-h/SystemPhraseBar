#import "ReviewTests.h"
#import "Language.h"
#import "BackupRetention.h"

int TestReviewChanges(void) {
    NSUInteger passed=0,total=0;
    for(NSArray *test in @[
        @[@[@"zh-Hans-CN",@"en"],@"zh-Hans"],
        @[@[@"zh-Hant-TW"],@"zh-Hans"],
        @[@[@"en-US",@"zh-Hans"],@"en"],
        @[@[@"ja-JP",@"zh-Hans"],@"en"],
        @[@[@"fr-FR"],@"en"],
        @[@[],@"en"]]) {
        total++; passed+=[LanguageForPreferences(test[0]) isEqual:test[1]];
    }
    total++;
    passed+=[L(@"Text Replacements") isEqual:[AppLanguage() isEqual:@"zh-Hans"] ? @"自定义短语" : @"Text Replacements"];
    total++;
    passed+=[L(@"GitHub repository") isEqual:[AppLanguage() isEqual:@"zh-Hans"] ? @"GitHub 仓库" : @"GitHub repository"];
    printf("localization (%s): %lu/%lu passed\n",AppLanguage().UTF8String,(unsigned long)passed,(unsigned long)total);
    BOOL languageOK=passed==total;

    NSFileManager *fm=NSFileManager.defaultManager;
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    NSURL *backups=[root URLByAppendingPathComponent:@"Backups" isDirectory:YES];
    [fm createDirectoryAtURL:backups withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *fixture=[NSPropertyListSerialization dataWithPropertyList:@[@{@"shortcut":@"fixture",@"phrase":@"test"}] format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
    NSMutableArray *created=[NSMutableArray array];
    for(NSUInteger index=0;index<30;index++) {
        NSURL *url=[backups URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"plist"]];
        [fixture writeToURL:url atomically:YES];
        [fm setAttributes:@{NSFileModificationDate:[NSDate dateWithTimeIntervalSince1970:1000+index]} ofItemAtPath:url.path error:nil];
        [created addObject:url];
    }
    NSURL *unknown=[backups URLByAppendingPathComponent:@"notes.plist"];
    [fixture writeToURL:unknown atomically:YES];
    NSURL *invalid=[backups URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"plist"]];
    [@"This is not a backup." writeToURL:invalid atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSURL *outside=[root URLByAppendingPathComponent:@"outside.txt"];
    [fixture writeToURL:outside atomically:YES];
    NSURL *symlink=[backups URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"plist"]];
    [fm createSymbolicLinkAtURL:symlink withDestinationURL:outside error:nil];
    NSURL *directory=[backups URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"plist"] isDirectory:YES];
    [fm createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:nil error:nil];
    passed=total=0;
    total++; passed+=PruneBackups(backups,BackupLimit,nil);
    NSUInteger surviving=0;
    BOOL newest=YES;
    for(NSUInteger index=0;index<created.count;index++) {
        BOOL exists=[fm fileExistsAtPath:[created[index] path]];
        surviving+=exists;
        if(exists!=(index>=10)) newest=NO;
    }
    total++; passed+=surviving==20 && newest;
    total++; passed+=[fm fileExistsAtPath:unknown.path] && [fm fileExistsAtPath:invalid.path];
    total++; passed+=[fm fileExistsAtPath:directory.path] && [fm destinationOfSymbolicLinkAtPath:symlink.path error:nil]!=nil;
    total++; passed+=[[NSData dataWithContentsOfURL:outside] isEqual:fixture];
    total++; passed+=PruneBackups([root URLByAppendingPathComponent:@"missing"],BackupLimit,nil);
    total++; passed+=!PruneBackups(outside,BackupLimit,nil);
    total++; passed+=PruneBackups(backups,BackupLimit-1,nil);
    NSURL *next=[backups URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"plist"]];
    [fixture writeToURL:next atomically:YES];
    surviving=1;
    for(NSURL *url in created) surviving+=[fm fileExistsAtPath:url.path];
    total++; passed+=surviving==20;
    printf("backup retention: %lu/%lu passed\n",(unsigned long)passed,(unsigned long)total);
    [fm removeItemAtURL:root error:nil];
    return !languageOK || passed!=total;
}
