
uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;

#if __VERSION__ >= 140

in vec3 aPos;
out vec3 objectPos;

#else

attribute vec3 aPos;

varying vec3 objectPos;

#endif


void main() {
    objectPos = aPos;
    gl_Position = projectionMatrix * viewMatrix * vec4(aPos, 1.0);
}
