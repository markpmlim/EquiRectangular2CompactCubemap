// Capture the six 2D sub-textures of a cubemap.

#ifdef GL_ES
precision mediump float;
#endif

#if __VERSION__ >= 140
in vec3 objectPos;

out vec4 FragColor;

#else

varying vec3 objectPos;

#endif

uniform sampler2D equirectangularImage;

#define M_PI 3.1415926535897932384626433832795
// invAtan = vec2(1/2π, 1/π)
const vec2 invAtan = vec2(1.0/(2.0*M_PI), 1.0/M_PI);
vec2 SampleSphericalMap(vec3 v) {

    // tan(θ) = v.z/v.x and sin(φ) = v.y/1.0
    vec2 uv = vec2(atan(v.x, v.z),
                   asin(v.y));

    // Range of uv.x: [-π, π]
    // Range of uv.y: [-π/2, π/2]
    uv *= invAtan;          // range of uv: [-0.5, 0.5]
    uv += 0.5;              // range of uv: [ 0.0, 1.0]
    return uv;

}

void main(void) {
    vec2 uv = SampleSphericalMap(normalize(objectPos));
#if __VERSION__ >= 140
    FragColor = texture(equirectangularImage, uv);
#else
    gl_FragColor = texture2D(equirectangularImage, uv);
#endif
}
