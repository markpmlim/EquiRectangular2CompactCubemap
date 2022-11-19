
#ifdef GL_ES
precision highp float;
#endif

#if __VERSION__ >= 140

in vec2 texCoords;

out vec4 FragColor;

#else

varying vec2 texCoords;

#endif


uniform samplerCube cubemap;

// OpenGL has a radians() function.
// Rotate an angle anti-clockwise about z-axis
vec2 rotate2d(vec2 uv, float angle) {
    float s = sin(radians(angle));
    float c = cos(radians(angle));
    return mat2(c, -s, s, c) * uv;
}
/*
 The six faces of the cubemap texture are displayed as upside down
  when run under Apple's OpenGL Profiler.
 We choose to map the texture coordinates in NDC space to a rectangular
  grid of dimensions 3:2 consisting of 12 squares, each of which
  1x1 unit squared.
 */
void main(void) {
    // Range from 0.0 to 1.0 for both u- and v-axes.
    vec2 inUV = texCoords;
    // Horizontal cross format
    // Range of inUV.x: [0.0, 1.0] ---> [0.0, 4.0]
    // Range of inUV.y: [0.0, 1.0] ---> [0.0, 3.0]
    inUV *= vec2(3.0, 2.0);
    // Default to this blue color
    FragColor.rgb = vec3(0.0, 0.0, 0.2);
    
    vec3 samplePos = vec3(0.0f);
    
    // Crude statement to visualize different cube map faces
    //  based on the grid coordinates
    int x = int(floor(inUV.x));     // 0, 1, 2
    int y = int(floor(inUV.y));     // 0, 1
    
    if (y == 1) {
        // Top row of 3 squares (-X, +Z, +X)
        // inUV.x: [0.0, 3.0] ---> uv.x: [0.0, 1.0]
        // inUV.y: [1.0, 2.0] ---> uv.y: [0.0, 1.0]
        vec2 uv = vec2(inUV.x - float(x),
                       inUV.y - 1.0);
        // Convert [0.0, 1.0] ---> [-1.0, 1.0]
        // uv.x: [0.0, 1.0] ---> [-1.0, 1.0]
        // uv.y: [0.0, 1.0] ---> [-1.0, 1.0]
        uv = 2.0 * uv - 1.0;
        // Now convert the uv coords into a 3D vector which will be
        //  used to access the correct face of the cube map.
        switch (x) {
            case 0: // NEGATIVE_X
                samplePos = vec3(-1.0f, uv.y, uv.x);
                break;
            case 1: // POSITIVE_Z
                samplePos = vec3( uv.x, uv.y, 1.0f);
                break;
            case 2: // POSITIVE_X
                samplePos = vec3( 1.0, uv.y,  -uv.x);
                break;
        }
    }
    else {
        // y = 0
        // Bottom row of 3 squares (-Y, -Z, +Y)
        // inUV.x: [0.0, 3.0] ---> uv.x: [0.0, 1.0]
        // inUV.y: [0.0, 1.0] ---> uv.y: [0.0, 1.0]
        vec2 uv = vec2(inUV.x - float(x),
                       inUV.y);
        // Convert [0.0, 1.0] ---> [-1.0, 1.0]
        uv = 2.0 * uv - 1.0;
        switch (x) {
            case 0: // NEGATIVE_Y
                uv = rotate2d(uv, 90.0);
                samplePos = vec3(uv.x, -1.0f,  uv.y);
                break;
            case 1: // NEGATIVE_Z
                uv = rotate2d(uv, -90.0);
                samplePos = vec3(-uv.x, uv.y, -1.0f);
                break;
            case 2: // POSITIVE_Y
                uv = rotate2d(uv, 90.0);
                samplePos = vec3(uv.x,  1.0f, -uv.y);
                break;
        }
    }

#if __VERSION__ >= 140
    if ((samplePos.x != 0.0f) && (samplePos.y != 0.0f)) {
        FragColor = vec4(texture(cubemap, samplePos).rgb, 1.0);
    }
#else
    if ((samplePos.x != 0.0f) && (samplePos.y != 0.0f)) {
        gl_FragColor = vec4(textureCube(cubemap, samplePos).rgb, 1.0);
    }
#endif
}
