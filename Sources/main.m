#import <Cocoa/Cocoa.h>
#import "Panel.h"
#import "Language.h"
#import "ReviewTests.h"
#import "Appearance.h"

static NSError *Await(void (^operation)(void (^)(NSError *))) {
    __block BOOL done=NO;
    __block NSError *result=nil;
    operation(^(NSError *error) { result=error; done=YES; });
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:15];
    while(!done && deadline.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.025]];
    return done ? result : [NSError errorWithDomain:@"Test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"test timed out"}];
}

static NSSet *Values(NSArray *entries) {
    NSMutableSet *values=[NSMutableSet set];
    for(NSDictionary *entry in entries) [values addObject:@[entry[@"shortcut"],entry[@"phrase"]]];
    return values;
}

static int IntegrationTest(SystemStore *store) {
    NSError *error=nil;
    NSArray *before=[store readEntries:&error];
    if(!before || !store.available) { puts("FAIL: cannot read system store or service unavailable"); return 1; }
    NSString *code=[@"zzphrasebarverify" stringByAppendingString:[NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""]];
    NSString *phrase=@"系统短语验证：中文・日本語・emoji 🐟";
    __block BOOL failed=NO;
    error=Await(^(void (^done)(NSError *)) { [store saveShortcut:code phrase:phrase original:nil completion:done]; });
    printf("add: %s\n",error ? "FAIL" : "PASS"); failed|=error!=nil;
    NSDictionary *(^find)(void)=^NSDictionary *{
        for(NSDictionary *entry in [store readEntries:nil]) if([entry[@"shortcut"] isEqual:code]) return entry;
        return nil;
    };
    NSDictionary *original=find();
    if(original) {
        error=Await(^(void (^done)(NSError *)) { [store saveShortcut:code phrase:@"不应覆盖重复输入码" original:nil completion:done]; });
        BOOL rejected=error && [find()[@"phrase"] isEqual:phrase];
        printf("duplicate rejected: %s\n",rejected ? "PASS" : "FAIL"); failed|=!rejected;
        error=Await(^(void (^done)(NSError *)) { [store saveShortcut:code phrase:@"已修改的系统短语 🐟" original:original completion:done]; });
        printf("edit: %s\n",error ? "FAIL" : "PASS"); failed|=error!=nil;
        error=Await(^(void (^done)(NSError *)) { [store saveShortcut:code phrase:@"不应覆盖过期记录" original:original completion:done]; });
        printf("stale edit rejected: %s\n",error ? "PASS" : "FAIL"); failed|=error==nil;
    }
    NSDictionary *latest=find();
    if(latest) {
        error=Await(^(void (^done)(NSError *)) { [store deleteEntry:latest completion:done]; });
        printf("delete: %s\n",error ? "FAIL" : "PASS"); failed|=error!=nil;
    }
    NSArray *after=[store readEntries:nil];
    BOOL restored=after && before.count==after.count && [Values(before) isEqual:Values(after)];
    printf("original system entries preserved: %s (%lu entries)\n",restored ? "PASS" : "FAIL",(unsigned long)after.count);
    return failed || !restored;
}

static int RenderDemo(NSString *path) {
    // Exercise the app's own view in an off-screen window with synthetic data.
    // This never reads or writes the user's phrases and is not a desktop capture.
    [NSApplication sharedApplication];
    PhrasePanel *panel=[PhrasePanel new];
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,440,550)
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    window.appearance=[NSAppearance appearanceNamed:[NSProcessInfo.processInfo.arguments containsObject:@"--dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    window.contentViewController=panel;
    if(@available(macOS 26.0,*)) {
        if(![panel.view isKindOfClass:NSGlassEffectView.class]) { puts("FAIL native glass surface"); return 1; }
        puts("native Liquid Glass surface: PASS");
    }
    NSImage *menuIcon=MenuBarIcon();
    if(!menuIcon.isTemplate || menuIcon.size.width!=18 || menuIcon.size.height!=18) { puts("FAIL menu bar template"); return 1; }
    NSBitmapImageRep *templateBitmap=[NSBitmapImageRep imageRepWithData:menuIcon.TIFFRepresentation];
    [[templateBitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[path.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"menubar-template.png"] atomically:YES];
    puts("menu bar template: PASS");
    BOOL chinese=[AppLanguage() isEqual:@"zh-Hans"];
    panel.entries=@[
        @{@"id":@1,@"shortcut":@"omw",@"phrase":chinese ? @"我已经在路上了。" : @"I'm on my way.",@"timestamp":@0},
        @{@"id":@2,@"shortcut":@"addr",@"phrase":chinese ? @"这里可以保存常用地址" : @"Your frequently used address",@"timestamp":@0},
        @{@"id":@3,@"shortcut":@"thanks",@"phrase":chinese ? @"谢谢，收到后我会尽快回复。" : @"Thanks! I'll get back to you soon.",@"timestamp":@0},
        @{@"id":@4,@"shortcut":@"brb",@"phrase":chinese ? @"稍等一下，我马上回来。" : @"One moment, I'll be right back.",@"timestamp":@0},
        @{@"id":@5,@"shortcut":@"review",@"phrase":chinese ? @"已收到，我会查看后回复。" : @"Received. I'll review it and reply.",@"timestamp":@0}];
    panel.search.stringValue=chinese ? @"路上" : @"way";
    [panel filter];
    if(panel.filtered.count!=1) { puts("FAIL search"); return 1; }
    panel.search.stringValue=@"";
    [panel filter];
    [panel newEntry:nil];
    panel.shortcut.stringValue=@"brb";
    panel.phrase.string=chinese ? @"稍等一下，我马上回来。" : @"One moment, I'll be right back.";
    [panel.view layoutSubtreeIfNeeded];
    BOOL editorLayout=panel.shortcut.frame.size.width>=300 && panel.editor.frame.size.height>150;
    if(![NSProcessInfo.processInfo.arguments containsObject:@"--editor"]) [panel cancelEdit:nil];
    if([NSProcessInfo.processInfo.arguments containsObject:@"--empty"]) { panel.entries=@[]; [panel filter]; }
    [panel.view layoutSubtreeIfNeeded];
    [panel.table tile];
    for(NSInteger row=0;row<panel.table.numberOfRows;row++) [panel.table viewAtColumn:0 row:row makeIfNecessary:YES];
    [window displayIfNeeded];
    BOOL layout=editorLayout;
    printf("synthetic UI search: PASS\neditor layout: %s\n",layout ? "PASS" : "FAIL");
    NSBitmapImageRep *bitmap=[panel.view bitmapImageRepForCachingDisplayInRect:panel.view.bounds];
    [panel.view cacheDisplayInRect:panel.view.bounds toBitmapImageRep:bitmap];
    NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    BOOL written=[png writeToFile:path atomically:YES];
    printf("offscreen demo render: %s\n",written ? "PASS" : "FAIL");
    return !layout || !written;
}

static int SelfTest(void) {
    NSUInteger failed=0, count=0;
    for(NSArray *test in @[
        @[@"0.2.0",@"0.1.9",@(NSOrderedDescending)],
        @[@"1.10.0",@"1.9.9",@(NSOrderedDescending)],
        @[@"v2.0.0",@"1.99.0",@(NSOrderedDescending)],
        @[@"1.0",@"1.0.0",@(NSOrderedSame)],
        @[@"1.0.0",@"1.0.0.0",@(NSOrderedSame)],
        @[@"0.1.0",@"0.2.0",@(NSOrderedAscending)]]) {
        count++;
        failed+=CompareVersions(test[0],test[1])!=[test[2] integerValue];
    }
    NSDictionary *valid=@{@"tag_name":@"v0.3.0",@"html_url":@"https://github.com/f-is-h/SystemPhraseBar/releases/tag/v0.3.0",@"draft":@NO,@"prerelease":@NO};
    for(NSDictionary *test in @[
        @{@"changes":@{},@"valid":@YES},
        @{@"changes":@{@"html_url":@"https://evil.example/releases/tag/v0.3.0"},@"valid":@NO},
        @{@"changes":@{@"html_url":@"http://github.com/f-is-h/SystemPhraseBar/releases/tag/v0.3.0"},@"valid":@NO},
        @{@"changes":@{@"html_url":@"https://github.com/other/repo/releases/tag/v0.3.0"},@"valid":@NO},
        @{@"changes":@{@"tag_name":@"v0.3.0-beta.1"},@"valid":@NO},
        @{@"changes":@{@"tag_name":NSNull.null},@"valid":@NO},
        @{@"changes":@{@"draft":@YES},@"valid":@NO},
        @{@"changes":@{@"prerelease":@YES},@"valid":@NO}]) {
        NSMutableDictionary *fixture=valid.mutableCopy;
        [fixture addEntriesFromDictionary:test[@"changes"]];
        NSData *data=[NSJSONSerialization dataWithJSONObject:fixture options:0 error:nil];
        count++;
        failed+=(ParseRelease(data,nil)!=nil)!=[test[@"valid"] boolValue];
    }
    for(NSData *data in @[NSData.data,[@"[]" dataUsingEncoding:NSUTF8StringEncoding],[@"invalid" dataUsingEncoding:NSUTF8StringEncoding]]) {
        count++; failed+=ParseRelease(data,nil)!=nil;
    }
    printf("update validation: %lu/%lu passed\n",(unsigned long)(count-failed),(unsigned long)count);
    return TestReviewChanges() || failed ? 1 : 0;
}

static int LoginTest(void) {
    SMAppService *service=SMAppService.mainAppService;
    SMAppServiceStatus before=service.status;
    if(before==SMAppServiceStatusRequiresApproval) {
        printf("login test requires system approval; no change made (status=%ld)\n",(long)before);
        return 2;
    }
    AppServices *services=[AppServices new];
    NSError *error=[services setLaunchAtLogin:YES];
    BOOL registered=!error && service.status==SMAppServiceStatusEnabled;
    printf("login register: %s (status=%ld)\n",registered ? "PASS" : "FAIL",(long)service.status);
    error=[services setLaunchAtLogin:NO];
    BOOL unregistered=!error && service.status==SMAppServiceStatusNotRegistered;
    printf("login unregister: %s (status=%ld)\n",unregistered ? "PASS" : "FAIL",(long)service.status);
    if(before==SMAppServiceStatusEnabled) error=[services setLaunchAtLogin:YES];
    BOOL restored=before==SMAppServiceStatusEnabled ? service.status==before : service.status==SMAppServiceStatusNotRegistered || service.status==SMAppServiceStatusNotFound;
    printf("login prior state restored: %s\n",restored ? "PASS" : "FAIL");
    return !registered || !unregistered || !restored;
}

static int CheckUpdate(void) {
    AppServices *services=[AppServices new];
    __block BOOL done=NO;
    __weak AppServices *weakServices=services;
    services.didChange=^{ if(!weakServices.checking) done=YES; };
    [services checkForUpdates:YES];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:25];
    while(!done && deadline.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.025]];
    printf("%s\n",services.updateMessage.UTF8String);
    services.didChange=nil;
    return done ? 0 : 1;
}

int main(int argc,const char *argv[]) {
    @autoreleasepool {
        NSArray *args=NSProcessInfo.processInfo.arguments;
        if([args containsObject:@"--self-test"]) return SelfTest();
        if([args containsObject:@"--login-test"]) return LoginTest();
        if([args containsObject:@"--login-status"]) { printf("login_status=%ld\n",(long)SMAppService.mainAppService.status); return 0; }
        if([args containsObject:@"--check-update"]) return CheckUpdate();
        if([args containsObject:@"--render-demo"] && args.count>=3) return RenderDemo(args.lastObject);
        if([args containsObject:@"--verify-system"] || [args containsObject:@"--integration-test"]) {
            SystemStore *store=[SystemStore new];
            if([args containsObject:@"--integration-test"]) return IntegrationTest(store);
            NSError *error=nil;
            NSArray *entries=[store readEntries:&error];
            printf("service_available=%s system_entries=%lu read_ok=%s\n",store.available ? "true" : "false",(unsigned long)entries.count,entries ? "true" : "false");
            return !store.available || !entries;
        }
        NSApplication *application=NSApplication.sharedApplication;
        AppDelegate *delegate=[AppDelegate new];
        application.delegate=delegate;
        [application run];
    }
    return 0;
}
