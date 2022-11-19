//
//  VirtualCamera.h
//  TexturedSphere
//
//  Created by Mark Lim Pak Mun on 30/07/2022.
//  Copyright © 2022 mark lim pak mun. All rights reserved.
//

#import <TargetConditionals.h>
#if (TARGET_OS_IOS || TARGET_OS_TV)
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

#import "AAPLMathUtilities.h"


@interface VirtualCamera : NSObject

- (nonnull instancetype) initWithScreenSize:(CGSize)size;

- (void) update:(float)duration;

- (void) resizeWithSize:(CGSize)newSize;

- (void) startDraggingFromPoint:(CGPoint)point;

- (void) dragToPoint:(CGPoint)point;

- (void) endDrag;

- (void) zoomInOrOut:(float)amount;

@property (nonatomic) vector_float3 position;
@property (nonatomic) matrix_float4x4 viewMatrix;
@property (nonatomic) simd_quatf orientation;
@property (nonatomic, getter=isDragging) BOOL dragging;

@end
