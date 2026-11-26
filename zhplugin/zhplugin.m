// zhplugin.m — EMPTY CONTROL BUILD (crash bisection experiment, 2026-11-26)
// Same dylib name (zhplugin.dylib), deliberately contains NO hooks and NO
// functionality: a single class with an empty +load and one log marker.
// Purpose: if Zhihu still exits with this loaded, the trigger is the mere
// presence of a foreign image, not plugin code.
#import <Foundation/Foundation.h>

@interface ZHPluginEmptyControl : NSObject
@end

@implementation ZHPluginEmptyControl
+ (void)load {
    NSLog(@"[zhplugin] empty control loaded");
}
@end
