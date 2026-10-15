#import "Language.h"
#import "AppServices.h"

NSString *const RepositoryURL=@"https://github.com/f-is-h/SystemPhraseBar";
NSString *const ReleasesAPIURL=@"https://api.github.com/repos/f-is-h/SystemPhraseBar/releases/latest";

static NSError *UpdateError(NSString *message) {
    return [NSError errorWithDomain:@"SystemPhraseBar.Update" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static NSArray<NSNumber *> *VersionParts(NSString *version) {
    if([version hasPrefix:@"v"]) version=[version substringFromIndex:1];
    NSRegularExpression *pattern=[NSRegularExpression regularExpressionWithPattern:@"^[0-9]+(\\.[0-9]+){1,3}$" options:0 error:nil];
    if(![pattern firstMatchInString:version options:0 range:NSMakeRange(0,version.length)]) return nil;
    NSMutableArray *parts=[NSMutableArray array];
    for(NSString *part in [version componentsSeparatedByString:@"."]) {
        if(part.length>9) return nil;
        [parts addObject:@(part.integerValue)];
    }
    while(parts.count<4) [parts addObject:@0];
    return parts;
}
NSComparisonResult CompareVersions(NSString *left, NSString *right) {
    NSArray *a=VersionParts(left), *b=VersionParts(right);
    if(!a || !b) return NSOrderedSame;
    for(NSUInteger i=0;i<4;i++) {
        NSComparisonResult result=[a[i] compare:b[i]];
        if(result!=NSOrderedSame) return result;
    }
    return NSOrderedSame;
}
NSDictionary *ParseRelease(NSData *data, NSError **error) {
    if(!data.length) { if(error) *error=UpdateError(L(@"The update response was empty. Try again later.")); return nil; }
    id json=[NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if(![json isKindOfClass:NSDictionary.class]) {
        if(error) *error=UpdateError(L(@"The update response was invalid. Try again later."));
        return nil;
    }
    NSString *tag=json[@"tag_name"], *urlString=json[@"html_url"];
    NSURL *url=[urlString isKindOfClass:NSString.class] ? [NSURL URLWithString:urlString] : nil;
    if(![tag isKindOfClass:NSString.class] || !VersionParts(tag) ||
        ![json[@"draft"] isKindOfClass:NSNumber.class] || ![json[@"prerelease"] isKindOfClass:NSNumber.class] ||
        [json[@"draft"] boolValue] || [json[@"prerelease"] boolValue] ||
        ![url.scheme isEqual:@"https"] || ![url.host isEqual:@"github.com"] || url.user || url.password || url.port ||
        ![url.path hasPrefix:@"/f-is-h/SystemPhraseBar/releases/tag/"]) {
        if(error) *error=UpdateError(L(@"No valid stable release was found."));
        return nil;
    }
    return @{@"version":[tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag,@"url":url};
}

@implementation AppServices {
    BOOL _checking;
    NSString *_updateMessage;
    NSString *_availableVersion;
    NSURL *_releaseURL;
    NSURLSession *_session;
    NSTimer *_timer;
}
- (instancetype)init {
    if((self=[super init])) _updateMessage=@"";
    return self;
}
- (NSString *)version { return [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0.0"; }
- (BOOL)checking { return _checking; }
- (NSString *)updateMessage { return _updateMessage; }
- (NSString *)availableVersion { return _availableVersion; }
- (NSURL *)releaseURL { return _releaseURL; }
- (SMAppServiceStatus)loginStatus { return SMAppService.mainAppService.status; }
- (void)notify { if(_didChange) _didChange(); }
- (void)start {
    // Only a normal user launch calls start. Tests and renders never register.
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    if(![defaults boolForKey:@"LoginDefaultAttempted"]) {
        [defaults setBool:YES forKey:@"LoginDefaultAttempted"];
        if(self.loginStatus==SMAppServiceStatusNotRegistered || self.loginStatus==SMAppServiceStatusNotFound) {
            NSError *error=[self setLaunchAtLogin:YES];
            if(error) _updateMessage=L(@"Launch at login could not be enabled. You can retry in the settings menu.");
        }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [self checkForUpdates:NO]; });
    _timer=[NSTimer scheduledTimerWithTimeInterval:3600 repeats:YES block:^(NSTimer *timer) { [self checkForUpdates:NO]; }];
    [self notify];
}
- (NSError *)setLaunchAtLogin:(BOOL)enabled {
    SMAppService *service=SMAppService.mainAppService;
    NSError *error=nil;
    if(enabled && (service.status==SMAppServiceStatusNotRegistered || service.status==SMAppServiceStatusNotFound)) [service registerAndReturnError:&error];
    else if(!enabled && (service.status==SMAppServiceStatusEnabled || service.status==SMAppServiceStatusRequiresApproval)) [service unregisterAndReturnError:&error];
    [self notify];
    return error;
}
- (void)checkForUpdates:(BOOL)manual {
    if(_checking) return;
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    NSDate *last=[defaults objectForKey:@"LastUpdateAttempt"];
    if(!manual && [last isKindOfClass:NSDate.class] && -last.timeIntervalSinceNow<24*3600) return;
    [defaults setObject:NSDate.date forKey:@"LastUpdateAttempt"];
    _checking=YES;
    if(manual) _updateMessage=L(@"Checking for updates…");
    [self notify];
    NSURLSessionConfiguration *configuration=NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.HTTPCookieStorage=nil;
    configuration.URLCache=nil;
    configuration.timeoutIntervalForRequest=15;
    configuration.timeoutIntervalForResource=20;
    _session=[NSURLSession sessionWithConfiguration:configuration];
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:ReleasesAPIURL]];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:[@"SystemPhraseBar/" stringByAppendingString:self.version] forHTTPHeaderField:@"User-Agent"];
    NSURLSession *session=_session;
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        NSError *error=networkError;
        NSDictionary *release=nil;
        if(!error && status==200 && data.length<=1024*1024) release=ParseRelease(data,&error);
        else if(!error && status!=404) error=UpdateError(status==403 || status==429 ? L(@"GitHub is limiting requests. Try again later.") : L(@"Could not read update information. Try again later."));
        dispatch_async(dispatch_get_main_queue(),^{
            self->_checking=NO;
            if(release && CompareVersions(release[@"version"],self.version)==NSOrderedDescending) {
                self->_availableVersion=release[@"version"];
                self->_releaseURL=release[@"url"];
                self->_updateMessage=[NSString stringWithFormat:L(@"Version v%@ is available"),self->_availableVersion];
            } else if(!error) {
                self->_availableVersion=nil;
                self->_releaseURL=nil;
                if(manual) self->_updateMessage=status==404 ? L(@"No stable release has been published yet.") : [NSString stringWithFormat:L(@"You are up to date: v%@"),self.version];
            } else if(manual) self->_updateMessage=networkError ? L(@"Could not connect to GitHub. Check your connection and try again.") : error.localizedDescription;
            [self notify];
        });
        [session finishTasksAndInvalidate];
    }] resume];
}
- (void)openRepository { [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:RepositoryURL]]; }
- (void)openRelease { if(_releaseURL) [NSWorkspace.sharedWorkspace openURL:_releaseURL]; }
@end
