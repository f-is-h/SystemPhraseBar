#import "Appearance.h"

NSView *MakeGlassSurface(NSView *content, BOOL interactive) {
    NSView *surface;
    if(@available(macOS 26.0,*)) {
        NSGlassEffectView *glass=[[NSGlassEffectView alloc] initWithFrame:content.frame];
        glass.style=NSGlassEffectViewStyleRegular;
        glass.cornerRadius=22;
        // No opaque tint: let macOS adapt the material and contrast itself.
        glass.contentView=content;
        if(@available(macOS 27.0,*)) {
            // This is a public macOS 27 property. Runtime lookup also allows SDK 26 builds.
            if([glass respondsToSelector:NSSelectorFromString(@"setEffectIsInteractive:")]) [glass setValue:@(interactive) forKey:@"effectIsInteractive"];
        }
        surface=glass;
    } else {
        NSVisualEffectView *material=[[NSVisualEffectView alloc] initWithFrame:content.frame];
        material.material=NSVisualEffectMaterialPopover;
        material.blendingMode=NSVisualEffectBlendingModeBehindWindow;
        material.state=NSVisualEffectStateActive;
        [material addSubview:content];
        surface=material;
    }
    content.translatesAutoresizingMaskIntoConstraints=NO;
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:surface.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:surface.bottomAnchor]
    ]];
    return surface;
}

NSImage *MenuBarIcon(void) {
    // An original optical reduction of AppIcon.svg, drawn as an alpha template.
    NSImage *image=[NSImage imageWithSize:NSMakeSize(18,18) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [NSColor.blackColor setStroke];
        NSBezierPath *card=[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(2,1.5,14,15) xRadius:3 yRadius:3];
        card.lineWidth=1.3;
        [card stroke];
        NSBezierPath *lines=[NSBezierPath bezierPath];
        lines.lineWidth=1.5;
        lines.lineCapStyle=NSLineCapStyleRound;
        lines.lineJoinStyle=NSLineJoinStyleRound;
        [lines moveToPoint:NSMakePoint(5,12)]; [lines lineToPoint:NSMakePoint(8.1,12)];
        [lines moveToPoint:NSMakePoint(5,5.5)]; [lines lineToPoint:NSMakePoint(11.2,5.5)];
        [lines moveToPoint:NSMakePoint(11.1,12)]; [lines lineToPoint:NSMakePoint(13,12)];
        [lines lineToPoint:NSMakePoint(13,8.7)]; [lines lineToPoint:NSMakePoint(9.3,8.7)];
        [lines moveToPoint:NSMakePoint(10.7,10.1)]; [lines lineToPoint:NSMakePoint(9.3,8.7)]; [lines lineToPoint:NSMakePoint(10.7,7.3)];
        [lines stroke];
        return YES;
    }];
    image.template=YES;
    image.accessibilityDescription=@"SystemPhraseBar";
    return image;
}
