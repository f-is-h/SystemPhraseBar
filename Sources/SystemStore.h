#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface SystemStore : NSObject
@property(nonatomic, readonly) BOOL available;
- (nullable NSArray<NSDictionary *> *)readEntries:(NSError **)error;
- (void)saveShortcut:(NSString *)shortcut phrase:(NSString *)phrase
           original:(nullable NSDictionary *)original
         completion:(void (^)(NSError * _Nullable))completion;
- (void)deleteEntry:(NSDictionary *)entry completion:(void (^)(NSError * _Nullable))completion;
@end
NS_ASSUME_NONNULL_END
