/*

 */

#if defined(TARGET_IOS) || defined(TARGET_TVOS)
@import UIKit;
#define PlatformViewBase UIView
#define PlatformViewController UIViewController
#else
@import AppKit;
#define PlatformViewBase NSOpenGLView
#define PlatformViewController NSViewController
#endif

@interface OpenGLView : PlatformViewBase

@end

@interface OpenGLViewController : PlatformViewController

@end
