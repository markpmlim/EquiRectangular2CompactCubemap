/*

 */

#import "AAPLMathUtilities.h"
#import "VirtualCamera.h"
#import "OpenGLRenderer.h"
#import <Foundation/Foundation.h>
#import <simd/simd.h>
#import <ModelIO/ModelIO.h>
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

// OpenGL textures are limited to 16K in size.
typedef NS_OPTIONS(NSUInteger, ImageSize) {
    QtrK        = 256,
    HalfK       = 512,
    OneK        = 1024,
    TwoK        = 2048,
    ThreeK      = 3072,
    FourK       = 4096,
    EightK      = 8192,
    SixteenK    = 16384
};

@implementation OpenGLRenderer {
    GLuint _defaultFBOName;
    CGSize _viewSize;

    GLuint _skyboxProgram;      // Display a skybox
    GLuint _glslProgram;        // Display a 2D image

    // For the skybox
    GLint _projectionMatrixLoc;
    GLint _modelMatrixLoc;

    GLuint _cubeVAO;
    GLuint _cubeVBO;
    GLuint _triangleVAO;

    // Textures created by this demo
    GLuint _equiRectTextureID;
    GLuint _cubemapTextureID;
    GLuint _eaCubemapTextureID;
    GLuint _compactTextureID;

    CGSize _tex0Resolution;

    matrix_float4x4 _projectionMatrix;
}

// Build all of the objects and setup initial state here.
- (instancetype)initWithDefaultFBOName:(GLuint)defaultFBOName {

    self = [super init];
    if(self) {
        NSLog(@"%s %s", glGetString(GL_RENDERER), glGetString(GL_VERSION));

        _defaultFBOName = defaultFBOName;
        [self buildResources];
        
        // Remember to set the *isHDR* flag correctly.
        _equiRectTextureID = [self textureWithContentsOfFile:@"jellybeans.png"
                                          resolution:&_tex0Resolution
                                               isHDR:NO];
        //printf("%f %f\n", tex0Resolution.width, tex0Resolution.height);
        // Set the target size of the 6 faces of the cubemap here.
        GLsizei faceSize = OneK;
        _cubemapTextureID = [self createCubemapTextureWithTexture:_equiRectTextureID
                                                     withFaceSize:faceSize];
 
        glBindVertexArray(_cubeVAO);
 
        // This GLSL program is only used for displaying a skybox.
        NSBundle *mainBundle = [NSBundle mainBundle];

        NSURL *vertexSourceURL = [mainBundle URLForResource:@"SkyboxVertexShader"
                                                withExtension:@"glsl"];
        NSURL *fragmentSourceURL = [mainBundle URLForResource:@"SkyboxFragmentShader"
                                                    withExtension:@"glsl"];
        _skyboxProgram = [OpenGLRenderer buildProgramWithVertexSourceURL:vertexSourceURL
                                                   withFragmentSourceURL:fragmentSourceURL];

        //printf("%u\n", _skyboxProgram);
        _projectionMatrixLoc = glGetUniformLocation(_skyboxProgram, "projectionMatrix");
        _modelMatrixLoc = glGetUniformLocation(_skyboxProgram, "modelMatrix");
        //printf("%d %d %d\n", _projectionMatrixLoc, _modelMatrixLoc);
        glBindVertexArray(0);

        glGenVertexArrays(1, &_triangleVAO);
        _eaCubemapTextureID = [self createEACTextureWithTexture:_cubemapTextureID
                                                   withFaceSize:faceSize];
        // Set the resolution of the compactmap correctly.
        // The max size of iOS and macOS textures are 4 096 and 16 384 respectively.
        CGSize resolutionEAC = CGSizeMake(3*faceSize, 2*faceSize);
        //CGSize resolutionEAC = CGSizeMake(3*1280, 3*1280*9.0/16.0);
        _compactTextureID = [self createCompactmapTextureWithEACTexture:_eaCubemapTextureID
                                                         withResolution:resolutionEAC];

        // Compile the vertex-fragment pair for drawing to the screen.
        glBindVertexArray(_triangleVAO);
        vertexSourceURL = [mainBundle URLForResource:@"SimpleVertexShader"
                                              withExtension:@"glsl"];
        fragmentSourceURL = [mainBundle URLForResource:@"SimpleFragmentShader"
                                                withExtension:@"glsl"];
        _glslProgram = [OpenGLRenderer buildProgramWithVertexSourceURL:vertexSourceURL
                                                 withFragmentSourceURL:fragmentSourceURL];
        // _viewSize is CGSizeZero but that's ok because the resize: method
        //  will be called shortly. The virtual camera's screen size will
        //  be set correctly.
        _camera = [[VirtualCamera alloc] initWithScreenSize:_viewSize];
    }

    return self;
}

- (void) dealloc {
    glDeleteProgram(_skyboxProgram);
    glDeleteProgram(_glslProgram);
    glDeleteVertexArrays(1, &_triangleVAO);
    glDeleteVertexArrays(1, &_cubeVAO);
    glDeleteBuffers(1, &_cubeVBO);
    glDeleteTextures(1, &_equiRectTextureID);
    glDeleteTextures(1, &_cubemapTextureID);
    glDeleteTextures(1, &_eaCubemapTextureID);
    glDeleteTextures(1, &_compactTextureID);
}


- (void)resize:(CGSize)size
{
    // Handle the resize of the draw rectangle. In particular, update the perspective projection matrix
    // with a new aspect ratio because the view orientation, layout, or size has changed.
    _viewSize = size;
    float aspect = (float)size.width / size.height;
    // Unused
    _projectionMatrix = matrix_perspective_right_hand_gl(radians_from_degrees(65.0f),
                                                         aspect,
                                                         1.0f, 5000.0);
    [_camera resizeWithSize:size];
}

/*
 Loading of 16-bit .hdr and 8-bit .png image files are supported.
 The image loaded is expected to be an Equirectangular image with
  a ratio resolution of 2:1.
 Both macOS and iOS support 16-bit textures.
 */
- (GLuint) textureWithContentsOfFile:(NSString *)name
                          resolution:(CGSize *)size
                               isHDR:(BOOL)isHDR {

    GLuint textureID = 0;

    NSBundle *mainBundle = [NSBundle mainBundle];
    if (isHDR == YES) {
        NSArray<NSString *> *subStrings = [name componentsSeparatedByString:@"."];
        NSString *path = [mainBundle pathForResource:subStrings[0]
                                              ofType:subStrings[1]];

        GLint width;
        GLint height;
        GLint nrComponents;

        // The following statement is necessary in OpenGL.
        stbi_set_flip_vertically_on_load(true);
        GLfloat *data = stbi_loadf([path UTF8String], &width, &height, &nrComponents, 0);
        // nrComponents should be 3 on return.
        if (data) {
            glGenTextures(1, &textureID);
            glBindTexture(GL_TEXTURE_2D, textureID);
            glTexImage2D(GL_TEXTURE_2D,
                         0,
                         GL_RGB16F,
                         width, height,
                         0,
                         GL_RGB,
                         GL_FLOAT,
                         data);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            stbi_image_free(data);
        }
        else {
            printf("Error reading hdr file\n");
            exit(1);
        }
    }
    else {
        // GLKTextureLoader has problems decoding big .jpg images so
        //  this demo only supports the loading of .png files.
        NSArray<NSString *> *subStrings = [name componentsSeparatedByString:@"."];

        NSURL* url = [mainBundle URLForResource: subStrings[0]
                                  withExtension: subStrings[1]];
        NSDictionary *loaderOptions = @{
            GLKTextureLoaderOriginBottomLeft : @YES,
        };
        NSError *error = nil;
        GLKTextureInfo *textureInfo = [GLKTextureLoader textureWithContentsOfURL:url
                                                                         options:loaderOptions
                                                                           error:&error];
        if (error == nil) {
            textureID = textureInfo.name;
            size->width = textureInfo.width;
            size->height = textureInfo.height;
        }
        else {
            NSLog(@"Error reading jpg/png file:%@", error);
            exit(2);
        }
    }
    return textureID;
}

- (void) buildResources {
    // initialize (if necessary) - From LearnOpenGL.com
    if (_cubeVAO == 0) {

        GLfloat vertices[] = {
            // back face
            //     positions           normals        texcoords
            -1.0f, -1.0f, -1.0f,  0.0f, 0.0f, -1.0f, 0.0f, 0.0f, // A bottom-left
             1.0f,  1.0f, -1.0f,  0.0f, 0.0f, -1.0f, 1.0f, 1.0f, // C top-right
             1.0f, -1.0f, -1.0f,  0.0f, 0.0f, -1.0f, 1.0f, 0.0f, // B bottom-right
             1.0f,  1.0f, -1.0f,  0.0f, 0.0f, -1.0f, 1.0f, 1.0f, // C top-right
            -1.0f, -1.0f, -1.0f,  0.0f, 0.0f, -1.0f, 0.0f, 0.0f, // A bottom-left
            -1.0f,  1.0f, -1.0f,  0.0f, 0.0f, -1.0f, 0.0f, 1.0f, // D top-left
            // front face
            -1.0f, -1.0f,  1.0f,  0.0f,  0.0f,  1.0f, 0.0f, 0.0f, // E bottom-left
             1.0f, -1.0f,  1.0f,  0.0f,  0.0f,  1.0f, 1.0f, 0.0f, // F bottom-right
             1.0f,  1.0f,  1.0f,  0.0f,  0.0f,  1.0f, 1.0f, 1.0f, // G top-right
             1.0f,  1.0f,  1.0f,  0.0f,  0.0f,  1.0f, 1.0f, 1.0f, // G top-right
            -1.0f,  1.0f,  1.0f,  0.0f,  0.0f,  1.0f, 0.0f, 1.0f, // H top-left
            -1.0f, -1.0f,  1.0f,  0.0f,  0.0f,  1.0f, 0.0f, 0.0f, // E bottom-left
            // left face
            -1.0f,  1.0f,  1.0f, -1.0f,  0.0f,  0.0f, 1.0f, 0.0f, // H top-right
            -1.0f,  1.0f, -1.0f, -1.0f,  0.0f,  0.0f, 1.0f, 1.0f, // D top-left
            -1.0f, -1.0f, -1.0f, -1.0f,  0.0f,  0.0f, 0.0f, 1.0f, // A bottom-left
            -1.0f, -1.0f, -1.0f, -1.0f,  0.0f,  0.0f, 0.0f, 1.0f, // A bottom-left
            -1.0f, -1.0f,  1.0f, -1.0f,  0.0f,  0.0f, 0.0f, 0.0f, // E bottom-right
            -1.0f,  1.0f,  1.0f, -1.0f,  0.0f,  0.0f, 1.0f, 0.0f, // H top-right
            // right face
            1.0f,  1.0f,  1.0f,  1.0f,  0.0f,  0.0f, 1.0f, 0.0f, // G top-left
            1.0f, -1.0f, -1.0f,  1.0f,  0.0f,  0.0f, 0.0f, 1.0f, // B bottom-right
            1.0f,  1.0f, -1.0f,  1.0f,  0.0f,  0.0f, 1.0f, 1.0f, // C top-right
            1.0f, -1.0f, -1.0f,  1.0f,  0.0f,  0.0f, 0.0f, 1.0f, // B bottom-right
            1.0f,  1.0f,  1.0f,  1.0f,  0.0f,  0.0f, 1.0f, 0.0f, // G top-left
            1.0f, -1.0f,  1.0f,  1.0f,  0.0f,  0.0f, 0.0f, 0.0f, // F bottom-left
            // bottom face
            -1.0f, -1.0f, -1.0f,  0.0f, -1.0f,  0.0f, 0.0f, 1.0f, // F top-right
             1.0f, -1.0f, -1.0f,  0.0f, -1.0f,  0.0f, 1.0f, 1.0f, // E Atop-left
             1.0f, -1.0f,  1.0f,  0.0f, -1.0f,  0.0f, 1.0f, 0.0f, // A bottom-left
             1.0f, -1.0f,  1.0f,  0.0f, -1.0f,  0.0f, 1.0f, 0.0f, // A bottom-left
            -1.0f, -1.0f,  1.0f,  0.0f, -1.0f,  0.0f, 0.0f, 0.0f, // B bottom-right
            -1.0f, -1.0f, -1.0f,  0.0f, -1.0f,  0.0f, 0.0f, 1.0f, // F top-right
            // top face
            -1.0f,  1.0f, -1.0f,  0.0f,  1.0f,  0.0f, 0.0f, 1.0f, // D top-left
             1.0f,  1.0f , 1.0f,  0.0f,  1.0f,  0.0f, 1.0f, 0.0f, // G bottom-right
             1.0f,  1.0f, -1.0f,  0.0f,  1.0f,  0.0f, 1.0f, 1.0f, // C top-right
             1.0f,  1.0f,  1.0f,  0.0f,  1.0f,  0.0f, 1.0f, 0.0f, // G bottom-right
            -1.0f,  1.0f, -1.0f,  0.0f,  1.0f,  0.0f, 0.0f, 1.0f, // D top-left
            -1.0f,  1.0f,  1.0f,  0.0f,  1.0f,  0.0f, 0.0f, 0.0f  // H bottom-left
        };

        glGenVertexArrays(1, &_cubeVAO);
        glGenBuffers(1, &_cubeVBO);
        // fill buffer
        glBindBuffer(GL_ARRAY_BUFFER, _cubeVBO);
        glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
        // link vertex attributes
        glBindVertexArray(_cubeVAO);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 8 * sizeof(GLfloat), (void*)0);
        glEnableVertexAttribArray(1);
        glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 8 * sizeof(GLfloat), (void*)(3 * sizeof(GLfloat)));
        glEnableVertexAttribArray(2);
        glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, 8 * sizeof(GLfloat), (void*)(6 * sizeof(GLfloat)));
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        glBindVertexArray(0);
    }
}

/*
 This method creates an ordinary cubemap texture from the EquiRectangular texture.
 The widely-used concept of placing a camera in 6 axes-aligned positions is
  used to capture the cubemap. The fragment shader projects the
  EquiRectangular image onto the six faces of the cube.

 Input:
    textureID: equiRectangular texture ID.
    faceSize: common size of the faces of the cubemap.

 Output:
    The cubemap's texture identifier/name if successful.
 */

- (GLuint) createCubemapTextureWithTexture:(GLuint)equiRectTextureID
                              withFaceSize:(GLsizei)faceSize {

    // Must do bind or buildProgramWithVertexSourceURL:withFragmentSourceURLwill crash on validation.
    glBindVertexArray(_cubeVAO);
    
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSURL *vertexSourceURL = [mainBundle URLForResource:@"CubemapVertexShader"
                                          withExtension:@"glsl"];
    NSURL *fragmentSourceURL = [mainBundle URLForResource:@"CubemapFragmentShader"
                                            withExtension:@"glsl"];
    GLuint equiRect2CubemapProgram = [OpenGLRenderer buildProgramWithVertexSourceURL:vertexSourceURL
                                                               withFragmentSourceURL:fragmentSourceURL];

    GLuint cubeMapID;
    glGenTextures(1, &cubeMapID);
    glBindTexture(GL_TEXTURE_CUBE_MAP, cubeMapID);

#if TARGET_MACOS
    // 8-bit and 16-bit equirectangular textures will be converted
    //  to cubemaps whose components are 32-bit floats.
    for (int i=0; i<6; i++) {
        glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + i,
                     0,
                     GL_RGBA32F,            // internal format
                     faceSize, faceSize,    // width, height
                     0,
                     GL_RGBA,               // format
                     GL_FLOAT,              // type
                     nil);                  // allocate space for the pixels.
    }
#else
    // 8-bit and 16-bit equirectangular textures will be converted
    //  to cubemaps whose components are 16-bit half floats.
    for (int i=0; i<6; i++) {
        glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + i,
                     0,
                     GL_RGBA16F,            // internal format
                     faceSize, faceSize,    // width, height
                     0,
                     GL_RGBA,               // format
                     GL_FLOAT,              // type
                     nil);                  // allocate space for the pixels.
    }
#endif
    GetGLError();

    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

    GLuint captureFBO;
    GLuint captureRBO;
    glGenFramebuffers(1, &captureFBO);
    glGenRenderbuffers(1, &captureRBO);
    
    glBindFramebuffer(GL_FRAMEBUFFER, captureFBO);
    glBindRenderbuffer(GL_RENDERBUFFER, captureRBO);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, faceSize, faceSize);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, captureRBO);
    GLenum framebufferStatus = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (framebufferStatus != GL_FRAMEBUFFER_COMPLETE) {
        printf("FrameBuffer is incomplete\n");
        GetGLError();

        glDeleteTextures(1, &cubeMapID);
        glDeleteFramebuffers(1, &captureFBO);
        glDeleteRenderbuffers(1, &captureRBO);
        glDeleteProgram(equiRect2CubemapProgram);
        return 0;
    }

    // Setup the common projection view matrix for the 6 camera positions.
    matrix_float4x4 captureProjectionMatrix = matrix_perspective_right_hand_gl(radians_from_degrees(90),
                                                                               1.0,
                                                                               0.1, 10.0);
 
    // Set up 6 view matrices for capturing data onto the six 2D textures of the cubemap.
    // Remember the virtual camera is inside the cube and at cube's centre.
    matrix_float4x4 captureViewMatrices[6];
    // The camera is rotated -90 degrees about the y-axis from its initial position.
    captureViewMatrices[0] = matrix_look_at_right_hand_gl((vector_float3){ 0,  0, 0},   // eye is at the centre of the cube.
                                                          (vector_float3){ 1,  0, 0},   // centre of +X face
                                                          (vector_float3){ 0, -1, 0});  // Up

    // The camera is rotated +90 degrees about the y-axis from its initial position.
    captureViewMatrices[1] = matrix_look_at_right_hand_gl((vector_float3){ 0,  0, 0},   // eye is at the centre of the cube.
                                                          (vector_float3){-1,  0, 0},   // centre of -X face
                                                          (vector_float3){ 0, -1, 0});  // Up
    
    // The camera is rotated -90 degrees about the x-axis from its initial position.
    captureViewMatrices[2] = matrix_look_at_right_hand_gl((vector_float3){ 0,  0, 0},   // eye is at the centre of the cube.
                                                          (vector_float3){ 0,  1, 0},   // centre of +Y face
                                                          (vector_float3){ 0,  0, 1});  // Up
    
    // The camera is rotated +90 degrees about the x-axis from its initial position.
    captureViewMatrices[3] = matrix_look_at_right_hand_gl((vector_float3){ 0,  0,  0},  // eye is at the centre of the cube.
                                                          (vector_float3){ 0, -1,  0},  // centre of -Y face
                                                          (vector_float3){ 0,  0, -1}); // Up
    
    // The camera is placed at its initial position pointing in the +z direction
    //  with its up vector pointing in the -y direction.
    captureViewMatrices[4] = matrix_look_at_right_hand_gl((vector_float3){ 0,  0, 0},   // eye is at the centre of the cube.
                                                          (vector_float3){ 0,  0, 1},   // centre of +Z face
                                                          (vector_float3){ 0, -1, 0});  // Up
    
    // The camera is rotated -180 (+180) degrees about the y-axis from its initial position.
    captureViewMatrices[5] = matrix_look_at_right_hand_gl((vector_float3){ 0,  0,  0},  // eye is at the centre of the cube.
                                                          (vector_float3){ 0,  0, -1},  // centre of -Z face
                                                          (vector_float3){ 0, -1,  0}); // Up

    glUseProgram(equiRect2CubemapProgram);
    GLint projectionMatrixLoc = glGetUniformLocation(equiRect2CubemapProgram, "projectionMatrix");
    GLint viewMatrixLoc = glGetUniformLocation(equiRect2CubemapProgram, "viewMatrix");
    //printf("%d %d\n", projectionMatrixLoc, viewMatrixLoc);
    glUniformMatrix4fv(projectionMatrixLoc, 1, GL_FALSE, (const GLfloat*)&captureProjectionMatrix);

    glBindFramebuffer(GL_FRAMEBUFFER, captureFBO);  // already bound
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, equiRectTextureID);

    for (unsigned int i = 0; i < 6; ++i) {
        glUniformMatrix4fv(viewMatrixLoc, 1, GL_FALSE, (const GLfloat*)&captureViewMatrices[i]);
        glFramebufferTexture2D(GL_FRAMEBUFFER,
                               GL_COLOR_ATTACHMENT0,
                               GL_TEXTURE_CUBE_MAP_POSITIVE_X + i,
                               cubeMapID,
                               0);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        glViewport(0, 0, faceSize, faceSize);
        [self renderCube];
    } // for

    glBindTexture(GL_TEXTURE_2D, 0);
    glUseProgram(0);

    // Clean up
    glDeleteFramebuffers(1, &captureFBO);
    glDeleteRenderbuffers(1, &captureRBO);
    glDeleteProgram(equiRect2CubemapProgram);

    glBindFramebuffer(GL_FRAMEBUFFER, _defaultFBOName);
    return cubeMapID;
}

/*
 This method creates an equi-angular cubemap texture from the cubemap texture
  that was instantiated by the above method.

 Input:
    textureID: cubemap texture ID
    faceSize: common size of the faces of a cube
 
 Output:
    The Equi-Angular Cubemap's texture identifier/name if successful.
 */

- (GLuint) createEACTextureWithTexture:(GLuint)cubemapID
                          withFaceSize:(GLsizei)faceSize {
    
    // Must do bind or buildProgramWithVertexSourceURL:withFragmentSourceURLwill crash on validation.
    glBindVertexArray(_triangleVAO);

    NSBundle *mainBundle = [NSBundle mainBundle];
    NSURL *vertexSourceURL = [mainBundle URLForResource:@"SimpleVertexShader"
                                          withExtension:@"glsl"];
    NSURL *fragmentSourceURL = [mainBundle URLForResource:@"EACFragmentShader"
                                            withExtension:@"glsl"];
    GLuint eacProgram = [OpenGLRenderer buildProgramWithVertexSourceURL:vertexSourceURL
                                                  withFragmentSourceURL:fragmentSourceURL];
    //printf("%u\n", eacProgram);
    GLint faceIndexLoc = glGetUniformLocation(eacProgram, "faceIndex");
    GLint cubemapLoc = glGetUniformLocation(eacProgram, "cubemap");
    
    GLuint eaCubemapID;
    glGenTextures(1, &eaCubemapID);
    glBindTexture(GL_TEXTURE_CUBE_MAP, eaCubemapID);
    
#if TARGET_MACOS
    for (int i=0; i<6; i++) {
        glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + i,
                     0,
                     GL_RGBA32F,            // internal format
                     faceSize, faceSize,    // width, height
                     0,
                     GL_RGBA,               // format
                     GL_FLOAT,              // type
                     nil);                  // allocate space for the pixels.
    }
#else
    for (int i=0; i<6; i++) {
        glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + i,
                     0,
                     GL_RGBA16F,            // internal format
                     faceSize, faceSize,    // width, height
                     0,
                     GL_RGBA,               // format
                     GL_FLOAT,              // type
                     nil);                  // allocate space for the pixels.
    }
#endif
    GetGLError();
    
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    
    GLuint captureFBO;
    GLuint captureRBO;
    glGenFramebuffers(1, &captureFBO);
    glGenRenderbuffers(1, &captureRBO);
    
    glBindFramebuffer(GL_FRAMEBUFFER, captureFBO);
    glBindRenderbuffer(GL_RENDERBUFFER, captureRBO);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, faceSize, faceSize);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, captureRBO);
    GLenum framebufferStatus = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (framebufferStatus != GL_FRAMEBUFFER_COMPLETE) {
        printf("FrameBuffer is incomplete\n");
        GetGLError();

        glDeleteProgram(eacProgram);
        glDeleteTextures(1, &eaCubemapID);
        glDeleteFramebuffers(1, &captureFBO);
        glDeleteRenderbuffers(1, &captureRBO);
        return 0;
    }
    
    
    glUseProgram(eacProgram);
    glBindFramebuffer(GL_FRAMEBUFFER, captureFBO);  // already bound
    glBindVertexArray(_triangleVAO);                // already bound
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_CUBE_MAP, cubemapID);

    for (unsigned int i = 0; i < 6; ++i) {
        glFramebufferTexture2D(GL_FRAMEBUFFER,
                               GL_COLOR_ATTACHMENT0,
                               GL_TEXTURE_CUBE_MAP_POSITIVE_X + i,
                               eaCubemapID,
                               0);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        glViewport(0, 0, faceSize, faceSize);
        glUniform1i(faceIndexLoc, i);
        glDrawArrays(GL_TRIANGLES, 0, 3);
    } // for

    glBindVertexArray(0);
    glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
    glUseProgram(0);

    // Clean up
    glDeleteFramebuffers(1, &captureFBO);
    glDeleteRenderbuffers(1, &captureRBO);
    glDeleteProgram(eacProgram);

    glBindFramebuffer(GL_FRAMEBUFFER, _defaultFBOName);
    return eaCubemapID;
}

/*
 The Equi-Angular Cubemap will be mapped to Google's compact map which
 is a 2 x 3 format. The ratio of width to height of this compact map is 16:9.
 Input:
    textureID: cubemap texture ID
    faceSize: common size of the faces of a cube
 
 Output:
    The cubemap's texture identifier/name if successful.
 */

- (GLuint) createCompactmapTextureWithEACTexture:(GLuint)cubemapID
                                  withResolution:(CGSize)size {
    
    // Must do bind or buildProgramWithVertexSourceURL:withFragmentSourceURL will crash on validation.
    glBindVertexArray(_triangleVAO);

    NSBundle *mainBundle = [NSBundle mainBundle];
    NSURL *vertexSourceURL = [mainBundle URLForResource:@"SimpleVertexShader"
                                          withExtension:@"glsl"];
    NSURL *fragmentSourceURL = [mainBundle URLForResource:@"CompactmapFragmentShader"
                                            withExtension:@"glsl"];
    GLuint compactmapProgram = [OpenGLRenderer buildProgramWithVertexSourceURL:vertexSourceURL
                                                         withFragmentSourceURL:fragmentSourceURL];
    //GLint cubemapLoc = glGetUniformLocation(compactmapProgram, "cubemap");
    //printf("%d\n", cubemapLoc);

    GLuint compactCubemapID;
    glGenTextures(1, &compactCubemapID);
    glBindTexture(GL_TEXTURE_2D, compactCubemapID);

#if TARGET_MACOS
    glTexImage2D(GL_TEXTURE_2D,
                 0,
                 GL_RGBA32F,                // internal format
                 size.width, size.height,   // width, height
                 0,
                 GL_RGBA,                   // format
                 GL_FLOAT,                  // type
                 nil);                      // allocate space for the pixels.
#else
    glTexImage2D(GL_TEXTURE_2D,
                 0,
                 GL_RGBA16F,                // internal format
                 size.width, size.height,   // width, height
                 0,
                 GL_RGBA,                   // format
                 GL_FLOAT,                  // type
                 nil);                      // allocate space for the pixels.
#endif
    GetGLError();

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

    GLuint captureFBO;
    GLuint captureRBO;
    glGenFramebuffers(1, &captureFBO);
    glGenRenderbuffers(1, &captureRBO);

    glBindFramebuffer(GL_FRAMEBUFFER, captureFBO);
    glBindRenderbuffer(GL_RENDERBUFFER, captureRBO);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, size.width, size.height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, captureRBO);
    GLenum framebufferStatus = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (framebufferStatus != GL_FRAMEBUFFER_COMPLETE) {
        printf("FrameBuffer is incomplete\n");
        GetGLError();
        
        glDeleteProgram(compactmapProgram);
        glDeleteTextures(1, &compactCubemapID);
        glDeleteFramebuffers(1, &captureFBO);
        glDeleteRenderbuffers(1, &captureRBO);
        return 0;
    }

    glUseProgram(compactmapProgram);

    glBindFramebuffer(GL_FRAMEBUFFER, captureFBO);  // already bound
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_CUBE_MAP, cubemapID);

    glFramebufferTexture2D(GL_FRAMEBUFFER,
                           GL_COLOR_ATTACHMENT0,
                           GL_TEXTURE_2D,
                           compactCubemapID,
                           0);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glViewport(0, 0, size.width, size.height);
    glBindVertexArray(_triangleVAO);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glBindVertexArray(0);
    glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
    glUseProgram(0);

    // Clean up
    glDeleteFramebuffers(1, &captureFBO);
    glDeleteRenderbuffers(1, &captureRBO);
    glDeleteProgram(compactmapProgram);

    // Restore
    glBindFramebuffer(GL_FRAMEBUFFER, _defaultFBOName);
    return compactCubemapID;
}


- (void) update {
    [_camera update:1.0f/60.0f];
}

- (void) renderCube {
    glBindVertexArray(_cubeVAO);
    glDrawArrays(GL_TRIANGLES, 0, 36);
    glBindVertexArray(0);
}

// Display compact map image on the screen.
- (void)draw {

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    // Bind the quad vertex array object.
    glClearColor(0.5, 0.5, 0.5, 1.0);
    glViewport(0, 0,
               _viewSize.width, _viewSize.height);
    glUseProgram(_glslProgram);
    glBindVertexArray(_triangleVAO);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, _compactTextureID);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glUseProgram(0);
    glBindVertexArray(0);
} // draw

/*
 This function is only used for debugging. Allows the user to look around
  the skybox. There might be seams at the edge between any 2 faces.
 Alternatively use Apple's OpenGL Profiler to check all the textures
  especially the 2 cubemap textures were created successfully.
 */
- (void)draw2 {

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glClearColor(0.5, 0.5, 0.5, 1.0);
    glViewport(0, 0,
               _viewSize.width, _viewSize.height);
    [self update];

    // We display the object (e.g. a textured sphere) here

    // The modelMatrix is the rotation matrix. No view matrix.
    matrix_float4x4 modelMatrix = simd_matrix4x4(_camera.orientation);
    glUseProgram(_skyboxProgram);

    glUniformMatrix4fv(_projectionMatrixLoc, 1, GL_FALSE, (const GLfloat*)&_projectionMatrix);
    glUniformMatrix4fv(_modelMatrixLoc, 1, GL_FALSE, (const GLfloat*)&modelMatrix);
    glActiveTexture(GL_TEXTURE0);
    //glBindTexture(GL_TEXTURE_CUBE_MAP, _cubemapTextureID);
    glBindTexture(GL_TEXTURE_CUBE_MAP, _eaCubemapTextureID);
    [self renderCube];
    glUseProgram(0);
} // draw


+ (GLuint)buildProgramWithVertexSourceURL:(NSURL*)vertexSourceURL
                    withFragmentSourceURL:(NSURL*)fragmentSourceURL {

    NSError *error;

    NSString *vertSourceString = [[NSString alloc] initWithContentsOfURL:vertexSourceURL
                                                                encoding:NSUTF8StringEncoding
                                                                   error:&error];

    NSAssert(vertSourceString, @"Could not load vertex shader source, error: %@.", error);

    NSString *fragSourceString = [[NSString alloc] initWithContentsOfURL:fragmentSourceURL
                                                                encoding:NSUTF8StringEncoding
                                                                   error:&error];

    NSAssert(fragSourceString, @"Could not load fragment shader source, error: %@.", error);

    // Prepend the #version definition to the vertex and fragment shaders.
    float  glLanguageVersion;

#if TARGET_IOS
    sscanf((char *)glGetString(GL_SHADING_LANGUAGE_VERSION), "OpenGL ES GLSL ES %f", &glLanguageVersion);
#else
    sscanf((char *)glGetString(GL_SHADING_LANGUAGE_VERSION), "%f", &glLanguageVersion);
#endif

    // `GL_SHADING_LANGUAGE_VERSION` returns the standard version form with decimals, but the
    //  GLSL version preprocessor directive simply uses integers (e.g. 1.10 should be 110 and 1.40
    //  should be 140). You multiply the floating point number by 100 to get a proper version number
    //  for the GLSL preprocessor directive.
    GLuint version = 100 * glLanguageVersion;

    NSString *versionString = [[NSString alloc] initWithFormat:@"#version %d", version];
#if TARGET_IOS
    if ([[EAGLContext currentContext] API] == kEAGLRenderingAPIOpenGLES3)
        versionString = [versionString stringByAppendingString:@" es"];
#endif

    vertSourceString = [[NSString alloc] initWithFormat:@"%@\n%@", versionString, vertSourceString];
    fragSourceString = [[NSString alloc] initWithFormat:@"%@\n%@", versionString, fragSourceString];

    GLuint prgName;

    GLint logLength, status;

    // Create a GLSL program object.
    prgName = glCreateProgram();

    /*
     * Specify and compile a vertex shader.
     */

    GLchar *vertexSourceCString = (GLchar*)vertSourceString.UTF8String;
    GLuint vertexShader = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(vertexShader, 1, (const GLchar **)&(vertexSourceCString), NULL);
    glCompileShader(vertexShader);
    glGetShaderiv(vertexShader, GL_INFO_LOG_LENGTH, &logLength);

    if (logLength > 0) {
        GLchar *log = (GLchar*) malloc(logLength);
        glGetShaderInfoLog(vertexShader, logLength, &logLength, log);
        NSLog(@"Vertex shader compile log:\n%s.\n", log);
        free(log);
    }

    glGetShaderiv(vertexShader, GL_COMPILE_STATUS, &status);

    NSAssert(status, @"Failed to compile the vertex shader:\n%s.\n", vertexSourceCString);

    // Attach the vertex shader to the program.
    glAttachShader(prgName, vertexShader);

    // Delete the vertex shader because it's now attached to the program, which retains
    // a reference to it.
    glDeleteShader(vertexShader);

    /*
     * Specify and compile a fragment shader.
     */

    GLchar *fragSourceCString =  (GLchar*)fragSourceString.UTF8String;
    GLuint fragShader = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(fragShader, 1, (const GLchar **)&(fragSourceCString), NULL);
    glCompileShader(fragShader);
    glGetShaderiv(fragShader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar*)malloc(logLength);
        glGetShaderInfoLog(fragShader, logLength, &logLength, log);
        NSLog(@"Fragment shader compile log:\n%s.\n", log);
        free(log);
    }

    glGetShaderiv(fragShader, GL_COMPILE_STATUS, &status);

    NSAssert(status, @"Failed to compile the fragment shader:\n%s.", fragSourceCString);

    // Attach the fragment shader to the program.
    glAttachShader(prgName, fragShader);

    // Delete the fragment shader because it's now attached to the program, which retains
    // a reference to it.
    glDeleteShader(fragShader);

    /*
     * Link the program.
     */

    glLinkProgram(prgName);
    glGetProgramiv(prgName, GL_LINK_STATUS, &status);
    NSAssert(status, @"Failed to link program.");
    if (status == 0) {
        glGetProgramiv(prgName, GL_INFO_LOG_LENGTH, &logLength);
        if (logLength > 0)
        {
            GLchar *log = (GLchar*)malloc(logLength);
            glGetProgramInfoLog(prgName, logLength, &logLength, log);
            NSLog(@"Program link log:\n%s.\n", log);
            free(log);
        }
    }

    // Added code
    // Call the 2 functions below if VAOs have been bound prior to creating the shader program
    // iOS will not complain if VAOs have NOT been bound.
    glValidateProgram(prgName);
    glGetProgramiv(prgName, GL_VALIDATE_STATUS, &status);
    NSAssert(status, @"Failed to validate program.");

    if (status == 0) {
        fprintf(stderr,"Program cannot run with current OpenGL State\n");
        glGetProgramiv(prgName, GL_INFO_LOG_LENGTH, &logLength);
        if (logLength > 0) {
            GLchar *log = (GLchar*)malloc(logLength);
            glGetProgramInfoLog(prgName, logLength, &logLength, log);
            NSLog(@"Program validate log:\n%s\n", log);
            free(log);
        }
    }

    GetGLError();

    return prgName;
}

@end
