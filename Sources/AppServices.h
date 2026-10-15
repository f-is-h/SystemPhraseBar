#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>

FOUNDATION_EXPORT NSString *const RepositoryURL;
FOUNDATION_EXPORT NSString *const ReleasesAPIURL;
FOUNDATION_EXPORT NSComparisonResult CompareVersions(NSString *left, NSString *right);
FOUNDATION_EXPORT NSDictionary *ParseRelease(NSData *data, NSError **error);

@interface AppServices : NSObject
@property(copy) void (^didChange)(void);
@property(readonly) BOOL checking;
@property(readonly) NSString *updateMessage;
@property(readonly) NSString *availableVersion;
@property(readonly) NSURL *releaseURL;
@property(readonly) NSString *version;
@property(readonly) SMAppServiceStatus loginStatus;
- (void)start;
- (void)checkForUpdates:(BOOL)manual;
- (NSError *)setLaunchAtLogin:(BOOL)enabled;
- (void)openRepository;
- (void)openRelease;
@end
