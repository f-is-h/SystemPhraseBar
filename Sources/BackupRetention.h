#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSUInteger const BackupLimit;
FOUNDATION_EXPORT NSURL *BackupDirectory(void);
FOUNDATION_EXPORT BOOL PruneBackups(NSURL *directory, NSUInteger keep, NSError **error);
