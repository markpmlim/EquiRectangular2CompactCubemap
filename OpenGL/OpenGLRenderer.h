/*

 */

#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#import <GLKit/GLKTextureLoader.h>
#import "OpenGLHeaders.h"

@class VirtualCamera;

@interface OpenGLRenderer : NSObject {
}

- (instancetype)initWithDefaultFBOName:(GLuint)defaultFBOName;

- (void)draw;

- (void)resize:(CGSize)size;

@property (nonatomic) VirtualCamera* _Nonnull camera;

// Give access to the View Controller object.
@property GLuint compactTextureID;

@end
