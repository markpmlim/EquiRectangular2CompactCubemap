
#if __VERSION__ >= 140

in vec3 aPos;
out vec3 objectPos;

#else

attribute vec3 aPos;
varying vec3 objectPos;

#endif

uniform mat4 projectionMatrix;
uniform mat4 modelMatrix;

void main()
{
    objectPos = aPos;

	vec4 clipPos = projectionMatrix * modelMatrix * vec4(objectPos, 1.0);

     gl_Position = clipPos.xyww;
}
