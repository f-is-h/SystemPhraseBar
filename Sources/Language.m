#import "Language.h"

NSString *LanguageForPreferences(NSArray<NSString *> *languages) {
    // Use the primary language only: Japanese + Chinese must still use English.
    return [languages.firstObject.lowercaseString hasPrefix:@"zh"] ? @"zh-Hans" : @"en";
}
NSString *AppLanguage(void) { return LanguageForPreferences(NSLocale.preferredLanguages); }
NSString *L(NSString *key) {
    static NSBundle *languageBundle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path=[NSBundle.mainBundle pathForResource:AppLanguage() ofType:@"lproj"];
        if(path) languageBundle=[NSBundle bundleWithPath:path];
    });
    return languageBundle ? [languageBundle localizedStringForKey:key value:key table:nil] : key;
}
