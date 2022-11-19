//
//  VirtualCamera.m
//  TexturedSphere
//
//  Created by Mark Lim Pak Mun on 30/07/2022.
//  Copyright © 2022 mark lim pak mun. All rights reserved.
//

#import "VirtualCamera.h"

@implementation VirtualCamera {
    matrix_float4x4 _viewMatrix;
    simd_quatf _orientation;
    BOOL _dragging;

    float _sphereRadius;
    CGSize _screenSize;

    // Use to compute the viewmatrix
    vector_float3 _eye;
    vector_float3 _target;
    vector_float3 _up;

    vector_float3 _startPoint;
    vector_float3 _endPoint;
    simd_quatf _previousQuat;
    simd_quatf _currentQuat;
}

- (instancetype) initWithScreenSize:(CGSize)size {
    self = [super init];
    if (self != nil) {
        _screenSize = size;
        _sphereRadius = 1.0f;

        _viewMatrix = matrix_identity_float4x4;
        _eye = vector_make(0.0f, 0.0f, 3.0f);
        _target = vector_make(0.0f, 0.0f, 0.0f);
        _up =  vector_make(0.0f, 1.0f, 0.0f);

        // Initialise to a quaternion identity.
        _orientation  = simd_quaternion(0.0f, 0.0f, 0.0f, 1.0f);
        _previousQuat = simd_quaternion(0.0f, 0.0f, 0.0f, 1.0f);
        _currentQuat  = simd_quaternion(0.0f, 0.0f, 0.0f, 1.0f);

        _startPoint = vector_make(0,0,0);
        _endPoint = vector_make(0,0,0);
    }
    return self;
}

- (void) setPosition:(vector_float3)position {
    _eye = position;
    [self updateViewMatrix];
}

-(void) updateViewMatrix {
    // Metal follows the left hand rule with +z direction into the screen.
    _viewMatrix = matrix_look_at_right_hand_gl(_eye,
                                               _target,
                                               _up);
    
}

- (void) update:(float)duration {
    _orientation = _currentQuat;
    [self updateViewMatrix];
}

// Handle resize.
- (void) resizeWithSize:(CGSize)newSize {
    _screenSize = newSize;
}

// helper methods
// The simd library function simd_quaternion(from, to) will compute
//  correctly if the angle between the 2 vectors is less than 90 degrees.
// Returns a rotation quaternion such that q*u = v
// Tutorial 17 RotationBetweenVectors quaternion_utils.cpp
-(simd_quatf) rotationBetweenVector:(vector_float3)from
                          andVector:(vector_float3)to {
    
    vector_float3 u = simd_normalize(from);
    vector_float3 v = simd_normalize(to);
    
    // Angle between the 2 vectors
    float cosTheta = simd_dot(u, v);
    vector_float3 rotationAxis;
    //float angle = acosf(cosTheta);
    //printf("angle:%f\n", degrees_from_radians(angle));
    if (cosTheta < -1 + 0.001f) {
        // Special case when vectors in opposite directions:
        //  there is no "ideal" rotation axis.
        // So guess one; any will do as long as it's perpendicular to u
        rotationAxis = simd_cross(vector_make(0.0f, 0.0f, 1.0f), u);
        float length2 = simd_dot(rotationAxis, rotationAxis);
        if ( length2 < 0.01f ) {
            // Bad luck, they were parallel, try again!
            rotationAxis = simd_cross(vector_make(1.0f, 0.0f, 0.0f), u);
        }
        
        rotationAxis = simd_normalize(rotationAxis);
        return simd_quaternion(radians_from_degrees(180.0f), rotationAxis);
    }
    
    // Compute rotation axis.
    rotationAxis = simd_cross(u, v);
    
    /*
     2cos^2(θ/2) - 1 = cosθ
     => cos(θ/2) = sqrt((1+cos0)/2)
     => cos(θ/2) = 0.5 * sqrt(2(1+cos0))
     
     sin(θ/2) = sqrt((1-cosθ)/2)
     = 1/sqrt(2(1+cos0))
     */
    
    float s = sqrt( (1+cosTheta)*2 );
    // Note: added a -ve sign.
    float invs = -1 / s;
    //float invs = 1 / s;
    // Normalising the axis should produce a unit quaternion.
    // The vector "rotationAxis" is normalised after multiplying
    //  it with the factor "invs"
    simd_quatf q = simd_quaternion(rotationAxis.x * invs,
                                   rotationAxis.y * invs,
                                   rotationAxis.z * invs,
                                   s * 0.5f);
    return q;
}

/*
 Project the mouse coords on to a sphere of radius 1.0 units.
 Use the mouse distance from the centre of screen as arc length on the sphere
    x = R * sin(a) * cos(b)
    y = R * sin(a) * sin(b)
    z = R * cos(a)
 where a = angle on x-z plane, b = angle on x-y plane

 NOTE:  the calculation of arc length is an estimation using linear distance
        from screen center (0,0) to the cursor position.

 */

- (vector_float3) projectMouseX:(float)x
                           andY:(float)y {
    
    float s = sqrtf(x*x + y*y);             // length between mouse coords and screen center
    float theta = s / _sphereRadius;        // s = r * θ
    float phi = atan2f(y, x);               // angle on x-y plane
    float x2 = _sphereRadius * sinf(theta); // x rotated by θ on x-z plane

    vector_float3 vec;
    vec.x = x2 * cosf(phi);
    vec.y = x2 * sinf(phi);
    vec.z = _sphereRadius * cosf(theta);

    return vec;

}


// Handle mouse interactions.

// Response to a mouse down.
- (void) startDraggingFromPoint:(CGPoint)point {
    self.dragging = YES;
    // The origin of macOS' display is at the bottom left corner.
    // Remap so that the origin is at the centre of the display.
    float mouseX = (2*point.x - _screenSize.width)/_screenSize.width;
    float mouseY = (2*point.y - _screenSize.height)/_screenSize.height;
    _startPoint = [self projectMouseX:mouseX
                                 andY:mouseY];
    // save it for the mouse dragged
    _previousQuat = _currentQuat;
}

// Respond to a mouse dragged
- (void) dragToPoint:(CGPoint)point {
    float mouseX = (2*point.x - _screenSize.width)/_screenSize.width;
    float mouseY = (2*point.y - _screenSize.height)/_screenSize.height;
    _endPoint = [self projectMouseX:mouseX
                               andY:mouseY];
    simd_quatf delta = [self rotationBetweenVector:_startPoint
                                         andVector:_endPoint];
    _currentQuat = simd_mul(delta, _previousQuat);
/*
    printf("point on sphere:%f %f %f    %f %f %f\n",
           _startPoint.x, _startPoint.y, _startPoint.z,
           _endPoint.x, _endPoint.y, _endPoint.z);
 */
}

// Response to a mouse up
- (void) endDrag {
    self.dragging = NO;
    _previousQuat = _currentQuat;
    _orientation = _currentQuat;
}

// Assume only a mouse with 1 scroll wheel.
- (void) zoomInOrOut:(float)amount {
    static float kmouseSensitivity = 0.1;
    vector_float3 pos = _eye;
    // OpenGL follows the right hand rule with +z direction out of the screen.
    float z = pos.z - amount*kmouseSensitivity;
    if (z >= 8.0f)
        z = 8.0f;
    else if (z <= 3.0f)
        z = 3.0f;
    _eye = vector_make(0.0, 0.0, z);
    self.position = _eye;
}

@end
