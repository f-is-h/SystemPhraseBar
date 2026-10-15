#import "Language.h"
#import "Panel.h"
#import "Appearance.h"
#import "BackupRetention.h"

static NSString *const SettingsURL=@"x-apple.systempreferences:com.apple.Keyboard-Settings.extension?TextReplacements";

static NSTextField *Label(NSString *text, CGFloat size, NSFontWeight weight) {
    NSTextField *view=[NSTextField labelWithString:text];
    view.font=[NSFont systemFontOfSize:size weight:weight];
    view.lineBreakMode=NSLineBreakByTruncatingTail;
    return view;
}
static NSStackView *Stack(NSArray *views, NSUserInterfaceLayoutOrientation orientation) {
    NSStackView *stack=[NSStackView stackViewWithViews:views];
    stack.orientation=orientation;
    stack.alignment=orientation==NSUserInterfaceLayoutOrientationVertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
    stack.spacing=10;
    stack.translatesAutoresizingMaskIntoConstraints=NO;
    return stack;
}
static NSView *Spacer(void) {
    NSView *view=[NSView new];
    [view setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    return view;
}
static NSButton *SymbolButton(NSString *symbol, NSString *help, id target, SEL action) {
    NSButton *button=[NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:help] target:target action:action];
    button.bezelStyle=NSBezelStyleAccessoryBarAction;
    button.bordered=NO;
    button.imagePosition=NSImageOnly;
    button.toolTip=help;
    button.accessibilityLabel=help;
    [button.widthAnchor constraintEqualToConstant:28].active=YES;
    [button.heightAnchor constraintEqualToConstant:28].active=YES;
    return button;
}
static NSBox *Separator(void) {
    NSBox *box=[NSBox new];
    box.boxType=NSBoxSeparator;
    return box;
}
@interface EditorWell : NSView
@end
@implementation EditorWell
- (void)drawRect:(NSRect)dirtyRect {
    NSBezierPath *path=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,0.5,0.5) xRadius:12 yRadius:12];
    [[NSColor.textBackgroundColor colorWithAlphaComponent:0.30] setFill]; [path fill];
    [[NSColor.separatorColor colorWithAlphaComponent:0.60] setStroke]; path.lineWidth=0.5; [path stroke];
}
@end

@interface PhrasePanel ()
@property NSStackView *list;
@property NSTextField *titleLabel;
@property NSTextField *subtitle;
@property NSTextField *count;
@property NSTextField *status;
@property NSTextField *empty;
@property NSTextField *editorTitle;
@property NSButton *back;
@property NSButton *add;
@property NSButton *edit;
@property NSButton *remove;
@property NSButton *save;
@property NSButton *cancel;
@property NSButton *download;
@property NSButton *more;
@property BOOL busy;
@end

@implementation PhrasePanel
- (instancetype)init {
    if((self=[super init])) { _store=[SystemStore new]; _services=[AppServices new]; _entries=@[]; _filtered=@[]; }
    return self;
}
- (void)loadView {
    NSView *content=[[NSView alloc] initWithFrame:NSMakeRect(0,0,440,550)];
    self.view=MakeGlassSurface(content,NO);
    NSImageView *icon=[NSImageView imageViewWithImage:[NSImage imageNamed:@"AppIcon"] ?: [NSImage imageWithSystemSymbolName:@"text.badge.plus" accessibilityDescription:nil]];
    [icon.widthAnchor constraintEqualToConstant:36].active=YES;
    [icon.heightAnchor constraintEqualToConstant:36].active=YES;
    _titleLabel=Label(@"SystemPhraseBar",16,NSFontWeightSemibold);
    _subtitle=Label(L(@"Text Replacements"),12,NSFontWeightRegular);
    _subtitle.textColor=NSColor.secondaryLabelColor;
    NSStackView *titles=Stack(@[_titleLabel,_subtitle],NSUserInterfaceLayoutOrientationVertical);
    titles.spacing=3;
    _back=SymbolButton(@"chevron.left",L(@"Back to phrases"),self,@selector(cancelEdit:));
    _back.hidden=YES;
    _add=SymbolButton(@"plus.circle.fill",L(@"Add phrase"),self,@selector(newEntry:));
    _add.contentTintColor=NSColor.controlAccentColor;
    _more=SymbolButton(@"ellipsis.circle",L(@"Settings and more"),self,@selector(showMenu:));
    NSStackView *header=Stack(@[_back,icon,titles,Spacer(),_add,_more],NSUserInterfaceLayoutOrientationHorizontal);

    _search=[[NSSearchField alloc] initWithFrame:NSMakeRect(0,0,380,28)];
    _search.placeholderString=L(@"Search shortcuts or phrases");
    _search.delegate=self;
    _search.sendsSearchStringImmediately=YES;
    _search.accessibilityLabel=L(@"Search phrases");
    _table=[[NSTableView alloc] initWithFrame:NSMakeRect(0,0,380,320)];
    _table.autoresizingMask=NSViewWidthSizable;
    NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:@"phrase"];
    column.width=380;
    column.resizingMask=NSTableColumnAutoresizingMask;
    [_table addTableColumn:column];
    _table.columnAutoresizingStyle=NSTableViewLastColumnOnlyAutoresizingStyle;
    _table.headerView=nil;
    _table.rowHeight=50;
    _table.intercellSpacing=NSMakeSize(0,1);
    _table.delegate=self;
    _table.dataSource=self;
    _table.target=self;
    _table.doubleAction=@selector(editEntry:);
    _table.style=NSTableViewStyleSourceList;
    _table.backgroundColor=NSColor.clearColor;
    _table.accessibilityLabel=L(@"Phrase list");
    NSScrollView *scroll=[NSScrollView new];
    scroll.documentView=_table;
    scroll.hasVerticalScroller=YES;
    scroll.drawsBackground=NO;
    scroll.borderType=NSNoBorder;
    _empty=[NSTextField wrappingLabelWithString:L(@"No phrases yet\nClick + to add your first phrase.")];
    _empty.alignment=NSTextAlignmentCenter;
    _empty.font=[NSFont systemFontOfSize:13];
    _empty.textColor=NSColor.secondaryLabelColor;
    _empty.translatesAutoresizingMaskIntoConstraints=NO;
    NSView *listContainer=[NSView new];
    scroll.translatesAutoresizingMaskIntoConstraints=NO;
    [listContainer addSubview:scroll];
    [listContainer addSubview:_empty];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:listContainer.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:listContainer.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:listContainer.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:listContainer.bottomAnchor],
        [_empty.centerXAnchor constraintEqualToAnchor:listContainer.centerXAnchor],
        [_empty.centerYAnchor constraintEqualToAnchor:listContainer.centerYAnchor],
        [_empty.widthAnchor constraintEqualToAnchor:listContainer.widthAnchor constant:-30]
    ]];
    _count=Label(@"",12,NSFontWeightRegular);
    _count.textColor=NSColor.secondaryLabelColor;
    _edit=SymbolButton(@"pencil",L(@"Edit selected phrase"),self,@selector(editEntry:));
    _remove=SymbolButton(@"trash",L(@"Delete selected phrase"),self,@selector(deleteEntry:));
    NSButton *refresh=SymbolButton(@"arrow.clockwise",L(@"Refresh phrases"),self,@selector(refreshAction:));
    NSStackView *listActions=Stack(@[_count,Spacer(),_edit,_remove,refresh],NSUserInterfaceLayoutOrientationHorizontal);
    listActions.spacing=5;
    _list=Stack(@[_search,listContainer,listActions],NSUserInterfaceLayoutOrientationVertical);

    _editorTitle=Label(L(@"Add phrase"),18,NSFontWeightSemibold);
    _shortcut=[NSTextField new];
    _shortcut.placeholderString=L(@"For example: omw");
    _shortcut.font=[NSFont monospacedSystemFontOfSize:14 weight:NSFontWeightRegular];
    _shortcut.accessibilityLabel=L(@"Shortcut");
    _shortcut.usesSingleLineMode=YES;
    _shortcut.maximumNumberOfLines=1;
    _shortcut.automaticTextCompletionEnabled=NO;
    _phrase=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,370,160)];
    _phrase.font=[NSFont systemFontOfSize:14];
    _phrase.richText=NO;
    _phrase.drawsBackground=NO;
    _phrase.automaticQuoteSubstitutionEnabled=NO;
    _phrase.automaticDashSubstitutionEnabled=NO;
    _phrase.automaticTextReplacementEnabled=NO;
    _phrase.automaticSpellingCorrectionEnabled=NO;
    _phrase.textContainerInset=NSMakeSize(10,10);
    _phrase.autoresizingMask=NSViewWidthSizable;
    _phrase.textContainer.widthTracksTextView=YES;
    _phrase.accessibilityLabel=L(@"Replacement phrase");
    NSScrollView *phraseScroll=[NSScrollView new];
    phraseScroll.documentView=_phrase;
    phraseScroll.hasVerticalScroller=YES;
    phraseScroll.borderType=NSNoBorder;
    phraseScroll.drawsBackground=NO;
    EditorWell *phraseWell=[EditorWell new];
    phraseScroll.translatesAutoresizingMaskIntoConstraints=NO;
    [phraseWell addSubview:phraseScroll];
    [NSLayoutConstraint activateConstraints:@[
        [phraseScroll.leadingAnchor constraintEqualToAnchor:phraseWell.leadingAnchor constant:4],
        [phraseScroll.trailingAnchor constraintEqualToAnchor:phraseWell.trailingAnchor constant:-4],
        [phraseScroll.topAnchor constraintEqualToAnchor:phraseWell.topAnchor constant:4],
        [phraseScroll.bottomAnchor constraintEqualToAnchor:phraseWell.bottomAnchor constant:-4]
    ]];
    _save=[NSButton buttonWithTitle:L(@"Save phrase") target:self action:@selector(saveEntry:)];
    _save.keyEquivalent=@"\r";
    _save.bezelStyle=NSBezelStyleRounded;
    _save.hasDestructiveAction=NO;
    _cancel=[NSButton buttonWithTitle:L(@"Cancel") target:self action:@selector(cancelEdit:)];
    NSStackView *editorActions=Stack(@[Spacer(),_cancel,_save],NSUserInterfaceLayoutOrientationHorizontal);
    NSTextField *hint=[NSTextField wrappingLabelWithString:L(@"Type the shortcut and macOS replaces it with your phrase.")];
    hint.font=[NSFont systemFontOfSize:11];
    hint.textColor=NSColor.secondaryLabelColor;
    _editor=Stack(@[_editorTitle,Label(L(@"Shortcut"),12,NSFontWeightMedium),_shortcut,Label(L(@"Phrase"),12,NSFontWeightMedium),phraseWell,hint,editorActions],NSUserInterfaceLayoutOrientationVertical);
    _editor.spacing=12;
    _editor.hidden=YES;
    _status=[NSTextField wrappingLabelWithString:@""];
    _status.font=[NSFont systemFontOfSize:11];
    _status.textColor=NSColor.secondaryLabelColor;
    _status.hidden=YES;
    _download=[NSButton buttonWithTitle:@"" target:self action:@selector(openRelease:)];
    _download.hidden=YES;
    NSBox *line=Separator();
    NSTextField *version=Label([@"v" stringByAppendingString:_services.version],10,NSFontWeightRegular);
    version.textColor=NSColor.secondaryLabelColor;
    NSTextField *footerHint=Label(L(@"Saved in macOS"),10,NSFontWeightRegular);
    footerHint.textColor=NSColor.secondaryLabelColor;
    NSStackView *footer=Stack(@[footerHint,Spacer(),version],NSUserInterfaceLayoutOrientationHorizontal);
    NSStackView *root=Stack(@[header,Separator(),_list,_editor,_status,_download,line,footer],NSUserInterfaceLayoutOrientationVertical);
    root.spacing=12;
    [content addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:18],
        [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-18],
        [root.topAnchor constraintEqualToAnchor:content.topAnchor constant:16],
        [root.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-12],
        [phraseWell.heightAnchor constraintGreaterThanOrEqualToConstant:120],
        [listContainer.heightAnchor constraintGreaterThanOrEqualToConstant:160],
        [_shortcut.heightAnchor constraintEqualToConstant:30]
    ]];
    for(NSView *view in root.arrangedSubviews) [view.widthAnchor constraintEqualToAnchor:root.widthAnchor].active=YES;
    for(NSStackView *section in @[_list,_editor]) for(NSView *view in section.arrangedSubviews) [view.widthAnchor constraintEqualToAnchor:section.widthAnchor].active=YES;
    [self updateButtons];
}
- (void)refresh {
    if(_busy) return;
    NSError *error=nil;
    NSArray *entries=[_store readEntries:&error];
    if(!entries) { _entries=@[]; [self message:error.localizedDescription error:YES]; }
    else { _entries=entries; if(_editor.hidden) [self message:@"" error:NO]; }
    [self filter];
}
- (void)refreshAction:(id)sender { [self refresh]; }
- (void)filter {
    NSString *query=_search.stringValue;
    _filtered=query.length ? [_entries filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *entry, NSDictionary *bindings) {
        return [entry[@"shortcut"] localizedStandardContainsString:query] || [entry[@"phrase"] localizedStandardContainsString:query];
    }]] : _entries;
    [_table reloadData];
    _count.stringValue=query.length ? [NSString stringWithFormat:L(@"%lu of %lu phrases"),(unsigned long)_filtered.count,(unsigned long)_entries.count] : [NSString stringWithFormat:L(@"%lu phrases"),(unsigned long)_entries.count];
    _empty.stringValue=query.length ? L(@"No matching phrases\nTry another shortcut or keyword.") : L(@"No phrases yet\nClick + to add your first phrase.");
    _empty.hidden=_filtered.count>0;
    [self updateButtons];
}
- (void)controlTextDidChange:(NSNotification *)notification { if(notification.object==_search) [self filter]; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return _filtered.count; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSTableCellView *cell=[tableView makeViewWithIdentifier:@"phrase" owner:self];
    if(!cell) {
        cell=[[NSTableCellView alloc] initWithFrame:NSMakeRect(0,0,404,50)];
        cell.identifier=@"phrase";
        NSTextField *code=Label(@"",14,NSFontWeightMedium);
        code.font=[NSFont monospacedSystemFontOfSize:14 weight:NSFontWeightMedium];
        code.tag=1;
        code.textColor=NSColor.secondaryLabelColor;
        NSTextField *text=Label(@"",16,NSFontWeightRegular);
        text.tag=2;
        NSStackView *stack=Stack(@[code,text],NSUserInterfaceLayoutOrientationVertical);
        stack.spacing=3;
        [cell addSubview:stack];
        NSBox *divider=Separator();
        divider.identifier=@"row-divider";
        divider.translatesAutoresizingMaskIntoConstraints=NO;
        [cell addSubview:divider];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:10],
            [stack.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-10],
            [stack.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor constant:-1],
            [code.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
            [text.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
            [divider.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:10],
            [divider.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-10],
            [divider.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor constant:-1]
        ]];
    }
    NSDictionary *entry=_filtered[row];
    for(NSView *view in cell.subviews) if([view.identifier isEqual:@"row-divider"]) view.hidden=row==(NSInteger)_filtered.count-1;
    ((NSTextField *)[cell viewWithTag:1]).stringValue=[entry[@"shortcut"] length] ? entry[@"shortcut"] : L(@"No shortcut");
    ((NSTextField *)[cell viewWithTag:2]).stringValue=[entry[@"phrase"] stringByReplacingOccurrencesOfString:@"\n" withString:@" ↵ "];
    return cell;
}
- (NSDictionary *)selected {
    NSInteger row=_table.selectedRow;
    return row>=0 && row<(NSInteger)_filtered.count ? _filtered[row] : nil;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification { [self updateButtons]; }
- (void)updateButtons {
    BOOL canEdit=!_busy && self.selected && _store.available;
    _edit.enabled=canEdit;
    _remove.enabled=canEdit;
    _add.enabled=!_busy && _store.available;
    _save.enabled=!_busy && _store.available;
    _back.enabled=!_busy;
    _cancel.enabled=!_busy;
    _shortcut.enabled=!_busy;
    _phrase.editable=!_busy;
}
- (void)setEditing:(BOOL)editing {
    _editor.hidden=!editing;
    _list.hidden=editing;
    _add.hidden=editing;
    _back.hidden=!editing;
    [self message:@"" error:NO];
}
- (void)newEntry:(id)sender {
    if(_busy) return;
    _original=nil;
    _shortcut.stringValue=@"";
    _phrase.string=@"";
    _editorTitle.stringValue=L(@"Add phrase");
    [self setEditing:YES];
    [self.view.window makeFirstResponder:_shortcut];
}
- (void)editEntry:(id)sender {
    if(_busy || !self.selected) return;
    _original=self.selected;
    _shortcut.stringValue=_original[@"shortcut"];
    _phrase.string=_original[@"phrase"];
    _editorTitle.stringValue=L(@"Edit phrase");
    [self setEditing:YES];
    [self.view.window makeFirstResponder:_shortcut];
}
- (void)cancelEdit:(id)sender { if(!_busy) { _original=nil; [self setEditing:NO]; } }
- (void)message:(NSString *)text error:(BOOL)error {
    _status.stringValue=text ?: L(@"Something went wrong.");
    _status.hidden=!text.length;
    _status.textColor=error ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
}
- (void)saveEntry:(id)sender {
    if(_busy) return;
    _busy=YES;
    [self updateButtons];
    [self message:L(@"Saving…") error:NO];
    [_store saveShortcut:_shortcut.stringValue phrase:_phrase.string original:_original completion:^(NSError *error) {
        self.busy=NO;
        if(!error) { self.original=nil; [self setEditing:NO]; [self refresh]; }
        [self message:error ? error.localizedDescription : L(@"Phrase saved.") error:error!=nil];
        [self updateButtons];
    }];
}
- (void)deleteEntry:(id)sender {
    NSDictionary *entry=self.selected;
    if(_busy || !entry) return;
    NSAlert *alert=[NSAlert new];
    alert.messageText=L(@"Delete this phrase?");
    alert.informativeText=L(@"This removes the phrase from macOS and may sync to your other devices through iCloud. A backup is saved first.");
    [alert addButtonWithTitle:L(@"Cancel")];
    [alert addButtonWithTitle:L(@"Delete")];
    alert.buttons.lastObject.hasDestructiveAction=YES;
    if([alert runModal]!=NSAlertSecondButtonReturn) return;
    _busy=YES;
    [self updateButtons];
    [_store deleteEntry:entry completion:^(NSError *error) {
        self.busy=NO;
        if(!error) { self.original=nil; [self setEditing:NO]; [self refresh]; }
        [self message:error ? error.localizedDescription : L(@"Phrase deleted.") error:error!=nil];
        [self updateButtons];
    }];
}
- (NSMenu *)contextMenu {
    NSMenu *menu=[NSMenu new];
    menu.autoenablesItems=NO;
    NSMenuItem *login=[NSMenuItem new];
    NSView *loginRow=[[NSView alloc] initWithFrame:NSMakeRect(0,0,238,38)];
    NSTextField *loginLabel=Label(L(@"Launch at login"),13,NSFontWeightRegular);
    loginLabel.frame=NSMakeRect(16,10,155,20);
    NSSwitch *toggle=[[NSSwitch alloc] initWithFrame:NSMakeRect(184,6,40,26)];
    toggle.target=self;
    toggle.action=@selector(toggleLogin:);
    toggle.accessibilityLabel=L(@"Launch at login");
    toggle.state=_services.loginStatus==SMAppServiceStatusEnabled || _services.loginStatus==SMAppServiceStatusRequiresApproval ? NSControlStateValueOn : NSControlStateValueOff;
    [loginRow addSubview:loginLabel];
    [loginRow addSubview:toggle];
    login.view=loginRow;
    [menu addItem:login];
    if(_services.loginStatus==SMAppServiceStatusRequiresApproval) [menu addItemWithTitle:L(@"Allow in Login Items…") action:@selector(openLoginSettings:) keyEquivalent:@""];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:L(@"GitHub repository") action:@selector(openRepository:) keyEquivalent:@""];
    NSMenuItem *update=[menu addItemWithTitle:_services.checking ? L(@"Checking for updates…") : L(@"Check for updates…") action:@selector(checkUpdate:) keyEquivalent:@""];
    update.enabled=!_services.checking;
    if(_services.availableVersion) [menu addItemWithTitle:[NSString stringWithFormat:L(@"Download v%@"),_services.availableVersion] action:@selector(openRelease:) keyEquivalent:@""];
    [menu addItemWithTitle:L(@"Text Replacement settings…") action:@selector(openSettings:) keyEquivalent:@""];
    [menu addItemWithTitle:L(@"Open backup folder") action:@selector(openBackups:) keyEquivalent:@""];
    NSMenuItem *retention=[menu addItemWithTitle:L(@"Keeps the 20 most recent backups") action:nil keyEquivalent:@""];
    retention.enabled=NO;
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:L(@"About") action:@selector(showAbout:) keyEquivalent:@""];
    NSMenuItem *quit=[menu addItemWithTitle:L(@"Quit SystemPhraseBar") action:@selector(terminate:) keyEquivalent:@"q"];
    for(NSMenuItem *item in menu.itemArray) if(item.action) item.target=self;
    quit.target=NSApp;
    return menu;
}
- (void)showMenu:(id)sender {
    [[self contextMenu] popUpMenuPositioningItem:nil atLocation:NSMakePoint(0,_more.bounds.size.height+4) inView:_more];
}
- (void)showAbout:(id)sender {
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *about=[NSAlert new];
    about.window.title=L(@"About");
    about.messageText=@"SystemPhraseBar";
    about.icon=[NSImage imageNamed:@"AppIcon"];
    about.informativeText=[NSString stringWithFormat:@"v%@\n\n%@\n\n© 2026 f-is-h · MIT",_services.version,L(@"A small menu bar app for macOS Text Replacements.")];
    [about addButtonWithTitle:L(@"Close")];
    [about addButtonWithTitle:L(@"GitHub repository")];
    if([about runModal]==NSAlertSecondButtonReturn) [_services openRepository];
}
- (void)toggleLogin:(NSSwitch *)sender {
    NSError *error=[_services setLaunchAtLogin:sender.state==NSControlStateValueOn];
    SMAppServiceStatus status=_services.loginStatus;
    sender.state=status==SMAppServiceStatusEnabled || status==SMAppServiceStatusRequiresApproval ? NSControlStateValueOn : NSControlStateValueOff;
    [self message:error ? L(@"Could not change launch at login. Check Login Items in System Settings.") : status==SMAppServiceStatusRequiresApproval ? L(@"Allow the app in Login Items to finish enabling launch at login.") : L(@"Launch at login setting saved.") error:error!=nil];
}
- (void)servicesChanged {
    if(!self.isViewLoaded) return;
    _download.hidden=!_services.availableVersion;
    _download.title=_services.availableVersion ? [NSString stringWithFormat:L(@"Download update v%@"),_services.availableVersion] : @"";
    if(_services.updateMessage.length) [self message:_services.updateMessage error:NO];
}
- (void)checkUpdate:(id)sender { [_services checkForUpdates:YES]; }
- (void)openRepository:(id)sender { [_services openRepository]; }
- (void)openRelease:(id)sender { [_services openRelease]; }
- (void)openSettings:(id)sender { [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:SettingsURL]]; }
- (void)openLoginSettings:(id)sender { [SMAppService openSystemSettingsLoginItems]; }
- (void)openBackups:(id)sender {
    NSURL *directory=BackupDirectory();
    if([NSFileManager.defaultManager fileExistsAtPath:directory.path]) [NSWorkspace.sharedWorkspace openURL:directory];
    else [self message:L(@"A backup will be created when you first save a phrase.") error:NO];
}
@end

@implementation AppDelegate {
    NSStatusItem *_item;
    NSPopover *_popover;
    PhrasePanel *_panel;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    _panel=[PhrasePanel new];
    _popover=[NSPopover new];
    _popover.contentViewController=_panel;
    _popover.contentSize=NSMakeSize(440,550);
    _popover.behavior=NSPopoverBehaviorTransient;
    _popover.delegate=self;
    _item=[NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    _item.button.image=MenuBarIcon();
    _item.button.toolTip=L(@"SystemPhraseBar · Custom phrases");
    _item.button.target=self;
    _item.button.action=@selector(toggle:);
    [_item.button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];
    __weak AppDelegate *weakSelf=self;
    _panel.services.didChange=^{ [weakSelf servicesChanged]; };
    if(![NSProcessInfo.processInfo.arguments containsObject:@"--preview"]) {
        [_panel.services start];
        NSError *error=nil;
        if(!PruneBackups(BackupDirectory(),BackupLimit,&error)) {
            (void)_panel.view;
            [_panel message:L(@"Old backups could not be cleaned up. Check the backup folder permissions.") error:YES];
        }
    }
    if([NSProcessInfo.processInfo.arguments containsObject:@"--show"]) [self toggle:nil];
}
- (void)servicesChanged { [_panel servicesChanged]; }
- (void)toggle:(id)sender {
    if(_popover.shown) [_popover performClose:nil];
    else {
        [NSApp activateIgnoringOtherApps:YES];
        [_popover showRelativeToRect:_item.button.bounds ofView:_item.button preferredEdge:NSRectEdgeMinY];
        [_panel refresh];
        [_panel servicesChanged];
        [_popover.contentViewController.view.window makeKeyWindow];
    }
}
@end
