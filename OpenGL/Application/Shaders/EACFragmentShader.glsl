//https://blog.google/products/google-ar-vr/bringing-pixels-front-and-center-vr-video/

#ifdef GL_ES
precision mediump float;
#endif

#if __VERSION__ >= 140
in vec2 texCoords;

out vec4 FragColor;

#else

varying vec2 texCoords;

#endif

#define PI 3.141592653589793

uniform samplerCube cubemap;
uniform int faceIndex;

void main() {
    // 2*px = tan(PI * (qu - 0.5) / 2.0);
    // 2*py = tan(PI * (qy - 0.5) / 2.0);
    // Range of texCoords:
    //  Initial: [0.0, 1.0];
    //  (texCoords - 0.5) --> [-0.5, 0.5]
    // Multiply by π/2 --> [-π/4, π/4]
    // Taking the tangent --> [-1.0, 1.0]
    vec2 uv = tan(PI / 2.0 * (texCoords - 0.5));

    // Note: we skip dividing by 2 because we want the range to be [-1.0, 1.0]
    vec3 dir = vec3(0);
    // Note: the switch statement is only available in GLSL 1.3 and above.
    // Reference:
    //  JVET-H1004: Algorithm descriptions of projection format conversion
    //  and video quality metrics in 360Lib
    //  Cubemap Projection Format (CMP) Table 3 pg 7
    switch(faceIndex) {
        case 0:
            // +X
            dir = vec3(1.0, -uv.y, -uv.x);
            break;
        case 1:
            // -X
            dir = vec3(-1.0, -uv.y, uv.x);
            break;
        case 2:
            // +Y
            dir = vec3(uv.x, 1.0, uv.y);
            break;
        case 3:
            // -Y
            dir = vec3(uv.x, -1.0, -uv.y);
            break;
        case 4:
            // +Z
            dir = vec3(uv.x, -uv.y, 1.0);
            break;
        case 5:
            // -Z
            dir = vec3(-uv.x, -uv.y, -1.0);
            break;
        default:
            break;
    }
#if __VERSION__ >= 140
    FragColor = texture(cubemap, dir);
#else
    gl_FragColor = textureCube(cubemap, dir);
#endif
}
