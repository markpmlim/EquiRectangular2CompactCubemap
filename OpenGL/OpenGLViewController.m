/*

 */
#import "OpenGLViewController.h"
#import "VirtualCamera.h"
#import "OpenGLRenderer.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#import "stb_image_write.h"


#ifdef TARGET_MACOS
#define PlatformGLContext NSOpenGLContext
#else // if!(TARGET_IOS || TARGET_TVOS)
#define PlatformGLContext EAGLContext
#endif // !(TARGET_IOS || TARGET_TVOS)

@implementation OpenGLView

#if defined(TARGET_IOS) || defined(TARGET_TVOS)
// Implement this to override the default layer class (which is [CALayer class]).
// We do this so that our view will be backed by a layer that is capable of OpenGL ES rendering.
+ (Class) layerClass
{
    return [CAEAGLLayer class];
}
#endif

@end

@implementation OpenGLViewController
{
    // Instance vars
    OpenGLView *_view;
    OpenGLRenderer *_openGLRenderer;
    PlatformGLContext *_context;
    GLuint _defaultFBOName;
    BOOL saveAsHDR;

#if defined(TARGET_IOS) || defined(TARGET_TVOS)
    GLuint _colorRenderbuffer;
    GLuint _depthRenderbuffer;
    CADisplayLink *_displayLink;
#else
    CVDisplayLinkRef _displayLink;
#endif
}

// Common method for iOS and macOS ports
- (void)viewDidLoad
{
    [super viewDidLoad];

    _view = (OpenGLView *)self.view;

    [self prepareView];

    [self makeCurrentContext];

    _openGLRenderer = [[OpenGLRenderer alloc] initWithDefaultFBOName:_defaultFBOName];

    if (!_openGLRenderer) {
        NSLog(@"OpenGL renderer failed initialization.");
        return;
    }
    saveAsHDR = NO;
    [_openGLRenderer resize:self.drawableSize];
}

#if TARGET_MACOS

- (CGSize) drawableSize {

    CGSize viewSizePoints = _view.bounds.size;

    CGSize viewSizePixels = [_view convertSizeToBacking:viewSizePoints];

    return viewSizePixels;
}

- (void)makeCurrentContext {

    [_context makeCurrentContext];
}

static CVReturn OpenGLDisplayLinkCallback(CVDisplayLinkRef displayLink,
                                          const CVTimeStamp* now,
                                          const CVTimeStamp* outputTime,
                                          CVOptionFlags flagsIn,
                                          CVOptionFlags* flagsOut,
                                          void* displayLinkContext) {

    OpenGLViewController *viewController = (__bridge OpenGLViewController*)displayLinkContext;

    [viewController draw];
    return YES;
}

// The CVDisplayLink object will call this method whenever a frame update is necessary.
- (void)draw {

    CGLLockContext(_context.CGLContextObj);

    [_context makeCurrentContext];

    [_openGLRenderer draw];

    CGLFlushDrawable(_context.CGLContextObj);
    CGLUnlockContext(_context.CGLContextObj);
}


- (void)prepareView {
 
    NSOpenGLPixelFormatAttribute attrs[] = {
        NSOpenGLPFAColorSize, 32,
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFADepthSize, 24,
        NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion3_2Core,
        0
    };

    NSOpenGLPixelFormat *pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];

    NSAssert(pixelFormat, @"No OpenGL pixel format.");

    _context = [[NSOpenGLContext alloc] initWithFormat:pixelFormat
                                          shareContext:nil];

    CGLLockContext(_context.CGLContextObj);

    [_context makeCurrentContext];

    CGLUnlockContext(_context.CGLContextObj);

    glEnable(GL_FRAMEBUFFER_SRGB);
    _view.pixelFormat = pixelFormat;
    _view.openGLContext = _context;
    _view.wantsBestResolutionOpenGLSurface = YES;

    // The default framebuffer object (FBO) is 0 on macOS, because it uses
    // a traditional OpenGL pixel format model. Might be different on other OSes.
    _defaultFBOName = 0;

    CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);

    // Set the renderer output callback function.
    CVDisplayLinkSetOutputCallback(_displayLink,
                                   &OpenGLDisplayLinkCallback, (__bridge void*)self);

    CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(_displayLink,
                                                      _context.CGLContextObj,
                                                      pixelFormat.CGLPixelFormatObj);
}

- (void)viewDidLayout {
    CGLLockContext(_context.CGLContextObj);

    NSSize viewSizePoints = _view.bounds.size;

    NSSize viewSizePixels = [_view convertSizeToBacking:viewSizePoints];

    [self makeCurrentContext];

    [_openGLRenderer resize:viewSizePixels];

    CGLUnlockContext(_context.CGLContextObj);

    if(!CVDisplayLinkIsRunning(_displayLink)) {
        CVDisplayLinkStart(_displayLink);
    }
}

- (void) viewDidAppear {
    [_view.window makeFirstResponder:self];
}

- (void) viewWillDisappear {
    CVDisplayLinkStop(_displayLink);
}

- (void) dealloc {
    CVDisplayLinkStop(_displayLink);
    CVDisplayLinkRelease(_displayLink);
}


- (void) mouseDown:(NSEvent *)event {
    NSPoint mouseLocation = [self.view convertPoint:event.locationInWindow
                                           fromView:nil];
    [_openGLRenderer.camera startDraggingFromPoint:mouseLocation];
}

- (void) mouseDragged:(NSEvent *)event {
    NSPoint mouseLocation = [self.view convertPoint:event.locationInWindow
                                           fromView:nil];
    if (_openGLRenderer.camera.isDragging) {
        [_openGLRenderer.camera dragToPoint:mouseLocation];
    }
}

- (void) mouseUp:(NSEvent *)event {
    NSPoint mouseLocation = [self.view convertPoint:event.locationInWindow
                                           fromView:nil];
    [_openGLRenderer.camera endDrag];
    
}

- (CGImageRef) makeCGImage:(void *)rawData
                     width:(NSUInteger)width
                    height:(NSUInteger)height
                colorSpace:(CGColorSpaceRef)colorSpace {
    
    NSUInteger pixelByteCount = 4;
    NSUInteger imageBytesPerRow = width * pixelByteCount;
    NSUInteger imageByteCount = imageBytesPerRow * height;
    NSUInteger bitsPerComponent = 8;
    // Assumes the raw data of CGImage is in RGB/RGBA format.
    // The alpha component is stored in the least significant bits of each pixel.
    CGImageAlphaInfo bitmapInfo = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big;
    // Let the function allocate memory for the bitmap
    CGContextRef bitmapContext = CGBitmapContextCreate(NULL,
                                                       width, height,
                                                       bitsPerComponent,
                                                       imageBytesPerRow,
                                                       colorSpace,
                                                       bitmapInfo);
    void* imageData = NULL;
    if (bitmapContext != NULL)
        imageData = CGBitmapContextGetData(bitmapContext);
    if (imageData != NULL)
        memcpy(imageData, rawData, imageByteCount);
    CGImageRef cgImage = CGBitmapContextCreateImage(bitmapContext);
    if (bitmapContext != NULL)
        CGContextRelease(bitmapContext);
    // The CGImage object might be NULL.
    // The caller need to release this CGImage object
    return cgImage;
}

/*
 Use the OpenGL function "glGetTexLevelParameteriv"  to query.
 Inputs:
    textureName: texture ID of a cubemap texture
    fileURL: location of the image on-disk representation.
    saveAsHDR must be set to YES/NO;
 Output:
    error: returned a custom NSError object
 */
- (BOOL) saveTexture:(GLuint)textureName
               toURL:(NSURL *)fileURL
               error:(NSError **)error {

    if ([fileURL.absoluteString containsString:@"."]) {
        if (error != NULL) {
            *error = [[NSError alloc] initWithDomain:@"File write failure."
                                                code:0xdeadbeef
                                            userInfo:@{NSLocalizedDescriptionKey : @"File extension provided."}];
        }
        return NO;
    }

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, textureName);

    // Use the OpenGL function "glGetTexLevelParameteriv" to query the texture object.
    GLint width, height;
    GLenum format;
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_WIDTH, &width);
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_HEIGHT, &height);
    printf("%d %d\n", width, height);
    // The following call should return 0x881B which is GL_RGB16F
    //  or 0x8058 which is GL_RGBA8
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_INTERNAL_FORMAT, (GLint*)&format);
    printf("0x%0X\n", format);

    int bits = 0;

    GLint _cbits;
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_RED_SIZE, &_cbits);
    bits += _cbits;
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_GREEN_SIZE, &_cbits);
    bits += _cbits;
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_BLUE_SIZE, &_cbits);
    bits += _cbits;

    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_ALPHA_SIZE, &_cbits);
    bits += _cbits;
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_DEPTH_SIZE, &_cbits);
    bits += _cbits;

    printf("# of bits per pixel:%d\n", bits);

    if (saveAsHDR == YES) {
        const size_t kSrcChannelCount = 3;
        // Note: each pixel is 4x4 = 16 bytes; we have instantiated the
        //  compactmap texture with an internal format of GL_RGBA32F for macOS.
        // However, the desired format and type is GL_RGB is GL_FLOAT respectively.
        const size_t bytesPerRow = width*kSrcChannelCount*sizeof(GLfloat);
        size_t dataSize = bytesPerRow*height;
        void *srcData = malloc(dataSize);
        BOOL isOK = YES;                    // Expect no errors

        // The size of ".hdr" files are usually bigger than other graphic types.
        // Create and allocate space for a new Pixel Buffer Object (pbo)
        GLuint  pbo;
        glGenBuffers(1, &pbo);
        // Bind the newly-created buffer object (pbo) to initialise it.
        glBindBuffer(GL_PIXEL_PACK_BUFFER, pbo);
        // NULL means allocate GPU memory to the PBO.
        // GL_STREAM_READ is a hint indicating the PBO will stream a texture download
        glBufferData(GL_PIXEL_PACK_BUFFER,
                     dataSize,
                     NULL,
                     GL_STREAM_READ);
        fileURL = [fileURL URLByAppendingPathExtension:@"hdr"];
        const char *filePath = [fileURL fileSystemRepresentation];
        // The parameters "format" and "type" are the pixel format
        //  and type of the desired data
        // Transfer texture into PBO
        glGetTexImage(GL_TEXTURE_2D,    // target
                      0,                // level of detail
                      GL_RGB,           // format
                      GL_FLOAT,         // type
                      NULL);

        // We are going to read data from the PBO. The call will only return when
        //  the GPU finishes its work with the buffer object.
        void *mappedPtr = glMapBuffer(GL_PIXEL_PACK_BUFFER, GL_READ_ONLY);
        // This should download the image's raw data from the GPU
        memcpy(srcData, mappedPtr, dataSize);
        // Release pointer to the mapping buffer
        glUnmapBuffer(GL_PIXEL_PACK_BUFFER);

        // Flip the image since it is upside down.
        void *destData = malloc(dataSize);
        // Start by reading the last row of the extracted image and
        //  writing the first row of the image to be output to disk.
        for (int srcRowNum = height - 1, destRowNum = 0; srcRowNum >= 0; srcRowNum--, destRowNum++) {
            // Copy the entire row in one shot
            memcpy(destData + (destRowNum * bytesPerRow),
                   srcData + (srcRowNum * bytesPerRow),
                   bytesPerRow);
        }

        int err = stbi_write_hdr(filePath,
                                 (int)width, (int)height,
                                 3,
                                 destData);
        if (err == 0) {
            if (error != NULL) {
                *error = [[NSError alloc] initWithDomain:@"File write failure."
                                                    code:0xdeadbeef
                                                userInfo:@{NSLocalizedDescriptionKey : @"Unable to write hdr file."}];
            }
            isOK = NO;
        }
        // Unbind and delete the buffer
        glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
        glDeleteBuffers(1, &pbo);
        free(srcData);
        free(destData);
        // Remove the binding associated with the target "GL_TEXTURE_2D".
        glBindTexture(GL_TEXTURE_2D, 0);
        return isOK;
    }
    else {
        // format == GL_RGBA8
        const size_t kSrcChannelCount = 4;
        const size_t bytesPerRow = width*kSrcChannelCount*sizeof(uint8_t);
        size_t dataSize = bytesPerRow*height;
        void *srcData = malloc(dataSize);
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        BOOL isOK = YES;                    // Expect no errors

        glGetTexImage(GL_TEXTURE_2D,        // target
                      0,                    // level of detail
                      GL_RGBA,              // format
                      GL_UNSIGNED_BYTE,     // type
                      srcData);

        // Flip the image since it is upside down.
        void *destData = malloc(dataSize);
        // Start by reading the last row of the extracted image and
        //  writing the first row of the image to be output to disk.
        for (int srcRowNum = height - 1, destRowNum = 0; srcRowNum >= 0; srcRowNum--, destRowNum++) {
            // Copy the entire row in one shot
            memcpy(destData + (destRowNum * bytesPerRow),
                   srcData + (srcRowNum * bytesPerRow),
                   bytesPerRow);
        }

        CGImageRef cgImage = [self makeCGImage:destData
                                         width:width
                                        height:height
                                    colorSpace:colorSpace];
        CGImageDestinationRef imageDestination = NULL;
        if (cgImage != NULL) {
            fileURL = [fileURL URLByAppendingPathExtension:@"png"];
            imageDestination = CGImageDestinationCreateWithURL((__bridge CFURLRef)fileURL,
                                                               kUTTypePNG,
                                                               1, NULL);
            CGImageDestinationAddImage(imageDestination, cgImage, nil);
            isOK = CGImageDestinationFinalize(imageDestination);
            CGImageRelease(cgImage);
            CFRelease(imageDestination);
            if (!isOK) {
                if (error != NULL) {
                    *error = [[NSError alloc] initWithDomain:@"File write failure."
                                                        code:0xdeadbeef
                                                    userInfo:@{NSLocalizedDescriptionKey : @"Unable to write png file."}];
                }
            }
        } // if cgImage not null
        else {
            if (error != NULL) {
                *error = [[NSError alloc] initWithDomain:@"File write failure."
                                                    code:0xdeadbeef
                                                userInfo:@{NSLocalizedDescriptionKey : @"Unable to write png file."}];
            }
            isOK = NO;
        } // cgImage is null
        CGColorSpaceRelease(colorSpace);
        free(srcData);
        free(destData);
        // Remove the binding associated with the target "GL_TEXTURE_2D".
        glBindTexture(GL_TEXTURE_2D, 0);
        return isOK;
    }
}

// Override inherited method
- (void) keyDown:(NSEvent *)event {
    if( [[event characters] length] ) {
        unichar nKey = [[event characters] characterAtIndex:0];
        if (nKey == 115) {
            GLuint textureID = _openGLRenderer.compactTextureID;
            if (textureID != 0) {
                NSSavePanel *sp = [NSSavePanel savePanel];
                sp.canCreateDirectories = YES;
                sp.nameFieldStringValue = @"image";
                sp.allowedFileTypes = @[@"hdr", @"png"];
                NSModalResponse buttonID = [sp runModal];
                if (buttonID == NSModalResponseOK) {
                    NSString* fileName = sp.nameFieldStringValue;
                    // Strip away the file extension; the program will append
                    //  it based on the flag "saveAsHDR".
                    if ([fileName containsString:@"."]) {
                        fileName = [fileName stringByDeletingPathExtension];
                    }
                    NSURL* folderURL = sp.directoryURL;
                    NSURL* fileURL = [folderURL URLByAppendingPathComponent:fileName];
                    NSError *err = nil;
                    if ([self saveTexture:textureID
                                    toURL:fileURL
                                    error:&err] == NO) {
                        NSLog(@"%@", err);
                    }
                }
            }
        }
        else {
            [super keyDown:event];
        }
    }
}
#else

// ===== iOS specific code. =====

// sender is an instance of CADisplayLink
- (void)draw:(id)sender
{
    [EAGLContext setCurrentContext:_context];
    [_openGLRenderer draw];

    glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderbuffer);
    [_context presentRenderbuffer:GL_RENDERBUFFER];
}

- (void)makeCurrentContext
{
    [EAGLContext setCurrentContext:_context];
}

- (void)prepareView
{
    CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.view.layer;

    eaglLayer.drawableProperties = @{kEAGLDrawablePropertyRetainedBacking : @NO,
                                     kEAGLDrawablePropertyColorFormat     : kEAGLColorFormatSRGBA8 };
    eaglLayer.opaque = YES;

    _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];

    if (!_context || ![EAGLContext setCurrentContext:_context])
    {
        NSLog(@"Could not create an OpenGL ES context.");
        return;
    }

    [self makeCurrentContext];

    self.view.contentScaleFactor = [UIScreen mainScreen].nativeScale;

    // In iOS & tvOS, you must create an FBO and attach a drawable texture
    // allocated by Core Animation to use as the default FBO for a view.
    glGenFramebuffers(1, &_defaultFBOName);
    glBindFramebuffer(GL_FRAMEBUFFER, _defaultFBOName);

    glGenRenderbuffers(1, &_colorRenderbuffer);

    glGenRenderbuffers(1, &_depthRenderbuffer);

    [self resizeDrawable];

    glFramebufferRenderbuffer(GL_FRAMEBUFFER,
                              GL_COLOR_ATTACHMENT0,
                              GL_RENDERBUFFER,
                              _colorRenderbuffer);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER,
                              GL_DEPTH_ATTACHMENT,
                              GL_RENDERBUFFER,
                              _depthRenderbuffer);

    // Create the display link so you render at 60 frames per second (FPS).
    _displayLink = [CADisplayLink displayLinkWithTarget:self
                                               selector:@selector(draw:)];

    _displayLink.preferredFramesPerSecond = 60;

    // Set the display link to run on the default run loop (and the main thread).
    [_displayLink addToRunLoop:[NSRunLoop currentRunLoop]
                       forMode:NSDefaultRunLoopMode];
}

- (CGSize)drawableSize
{
    GLint backingWidth, backingHeight;
    glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderbuffer);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &backingHeight);
    CGSize drawableSize = {backingWidth, backingHeight};
    return drawableSize;
}

- (void)resizeDrawable
{
    [self makeCurrentContext];

    // First, ensure that you have a render buffer.
    assert(_colorRenderbuffer != 0);

    glBindRenderbuffer(GL_RENDERBUFFER,
                       _colorRenderbuffer);
    // This call associates the storage for the current render buffer with the EAGLDrawable (our CAEAGLLayer)
    // allowing us to draw into a buffer that will later be rendered to screen wherever the
    // layer is (which corresponds with our view).
    [_context renderbufferStorage:GL_RENDERBUFFER
                     fromDrawable:(id<EAGLDrawable>)_view.layer];

    CGSize drawableSize = [self drawableSize];

    glBindRenderbuffer(GL_RENDERBUFFER,
                       _depthRenderbuffer);

    glRenderbufferStorage(GL_RENDERBUFFER,
                          GL_DEPTH_COMPONENT24,
                          drawableSize.width, drawableSize.height);

    GetGLError();
    // The custom render object is nil on first call to this method.
    [_openGLRenderer resize:self.drawableSize];
}

// overridden method
- (void)viewDidLayoutSubviews
{
    [self resizeDrawable];
}

// overridden method
- (void)viewDidAppear:(BOOL)animated
{
    [self resizeDrawable];
}

#endif
@end
