#import <Cocoa/Cocoa.h>
#import "SystemStore.h"
#import "AppServices.h"

@interface PhrasePanel : NSViewController <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@property SystemStore *store;
@property AppServices *services;
@property NSArray<NSDictionary *> *entries;
@property NSArray<NSDictionary *> *filtered;
@property NSDictionary *original;
@property NSTableView *table;
@property NSSearchField *search;
@property NSStackView *editor;
@property NSTextField *shortcut;
@property NSTextView *phrase;
- (void)refresh;
- (void)filter;
- (void)newEntry:(id)sender;
- (void)cancelEdit:(id)sender;
- (void)servicesChanged;
- (NSMenu *)contextMenu;
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSPopoverDelegate>
@end
