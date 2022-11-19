#ifdef GL_ES
precision mediump float;
#endif

#if __VERSION__ >= 140

in vec3 objectPos;

out vec4 FragColor;

#else

varying vec3 objectPos;

#endif

uniform samplerCube cubemapTexture;

void main()
{
    // We need to reverse the z-direction
    vec3 direction = normalize(vec3(objectPos.x, objectPos.y, -objectPos.z));

#if __VERSION__ >= 140
    FragColor = texture(cubemapTexture, direction);
#else
    gl_FragColor = textureCube(cubemapTexture, direction);
#endif
}
