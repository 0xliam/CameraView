//
//  ViewController.m
//  CameraView
//
//  Created by Liam Patterson on 9/28/15.
//  Copyright © 2015 Liam Patterson. All rights reserved.
//

#import "ViewController.h"
#import "UIView+CameraFeed.h"
#import <QuartzCore/QuartzCore.h>

@import AVFoundation;
@import Photos;
@import QuartzCore;
@import AVKit;

static void * CapturingStillImageContext = &CapturingStillImageContext;
static void * SessionRunningContext = &SessionRunningContext;

typedef NS_ENUM( NSInteger, AVCamSetupResult ) {
    AVCamSetupResultSuccess,
    AVCamSetupResultCameraNotAuthorized,
    AVCamSetupResultSessionConfigurationFailed
};

@interface ViewController () <AVCaptureFileOutputRecordingDelegate>
@property (nonatomic, weak) IBOutlet UIButton *recordButton;


@property (nonatomic, weak) IBOutlet CameraFeed *camfeed;

@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (nonatomic) AVCaptureMovieFileOutput *movieFileOutput;
@property (nonatomic) AVCaptureStillImageOutput *stillImageOutput;

@property (nonatomic) AVCamSetupResult setupResult;
@property (nonatomic, getter=isSessionRunning) BOOL sessionRunning;
@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;

@end

@implementation ViewController




- (void)viewDidLoad {
    
    [super viewDidLoad];
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationNone];
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationNone];
    
    //
    
    // Do any additional setup after loading the view, typically from a nib.
    self.recordButton.enabled = NO;
    self.recordButton.hidden = YES;
    
    //tap gesture: two fingers
    UITapGestureRecognizer * r = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(viewWasTwoFingerTapped:)];
    [r setNumberOfTouchesRequired:2];
    [[self view] addGestureRecognizer:r];
    //tap gesture: three fingers
    UITapGestureRecognizer * s = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(viewWasThreeFingerTapped:)];
    [s setNumberOfTouchesRequired:3];
    [[self view] addGestureRecognizer:s];
   
    
    

    
    self.session = [[AVCaptureSession alloc] init];
    
    self.camfeed.session = self.session;
  
    self.sessionQueue = dispatch_queue_create( "session queue", DISPATCH_QUEUE_SERIAL );
    
    self.setupResult = AVCamSetupResultSuccess;

    
    /*
    AVCaptureVideoPreviewLayer *previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    [previewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    
    previewLayer.frame = self.camfeed.bounds;
    [self.camfeed.layer addSublayer:previewLayer];
     
    */
    
   //button animation setup
//    CGRect screenBound = [[UIScreen mainScreen] bounds];
//    CGSize screenSize = screenBound.size;
//    CGFloat screenWidth = screenSize.width;
//    CGFloat screenHeight = screenSize.height;
 //   CALayer *recordButton = nil;
 //   recordButton = [CALayer layer];
//    recordButton.bounds = CGRectMake(0, 0, screenHeight, screenWidth);
//    recordButton.position = CGPointMake(screenHeight/2, screenWidth/2);
//    recordButton.backgroundColor = [UIColor whiteColor].CGColor;
//    recordButton.opacity = 1.0f;
//    [recordButton addSublayer:self.recordButton.layer];
//    [self.view.layer addSublayer:recordButton];
    
    //
    // Check video authorization status. Video access is required and audio access is optional.
    // If audio access is denied, audio is not recorded during movie recording.
    switch ( [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] )
    {
        case AVAuthorizationStatusAuthorized:
        {
            // The user has previously granted access to the camera.
            break;
        }
        case AVAuthorizationStatusNotDetermined:
        {
            // The user has not yet been presented with the option to grant video access.
            // We suspend the session queue to delay session setup until the access request has completed to avoid
            // asking the user for audio access if video access is denied.
            // Note that audio access will be implicitly requested when we create an AVCaptureDeviceInput for audio during session setup.
            dispatch_suspend( self.sessionQueue );
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^( BOOL granted ) {
                if ( ! granted ) {
                    self.setupResult = AVCamSetupResultCameraNotAuthorized;
                }
                dispatch_resume( self.sessionQueue );
            }];
            break;
        }
        default:
        {
            // The user has previously denied access.
            self.setupResult = AVCamSetupResultCameraNotAuthorized;
            break;
        }
    }

    //
    
    
    // Setup the capture session.
    // In general it is not safe to mutate an AVCaptureSession or any of its inputs, outputs, or connections from multiple threads at the same time.
    // Why not do all of this on the main queue?
    // Because -[AVCaptureSession startRunning] is a blocking call which can take a long time. We dispatch session setup to the sessionQueue
    // so that the main queue isn't blocked, which keeps the UI responsive.
    dispatch_async( self.sessionQueue, ^{
        if ( self.setupResult != AVCamSetupResultSuccess ) {
            return;
        }
        
        self.backgroundRecordingID = UIBackgroundTaskInvalid;
        NSError *error = nil;
        
        AVCaptureDevice *videoDevice = [ViewController deviceWithMediaType:AVMediaTypeVideo preferringPosition:AVCaptureDevicePositionBack];
        AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
        
        if ( ! videoDeviceInput ) {
            NSLog( @"Could not create video device input: %@", error );
        }
        
        [self.session beginConfiguration];
        
        if ( [self.session canAddInput:videoDeviceInput] ) {
            [self.session addInput:videoDeviceInput];
            self.videoDeviceInput = videoDeviceInput;
            
            dispatch_async( dispatch_get_main_queue(), ^{
                                UIInterfaceOrientation statusBarOrientation = [UIApplication sharedApplication].statusBarOrientation;
                AVCaptureVideoOrientation initialVideoOrientation = AVCaptureVideoOrientationPortrait;
                if ( statusBarOrientation != UIInterfaceOrientationUnknown ) {
                    initialVideoOrientation = (AVCaptureVideoOrientation)statusBarOrientation;
                }
                
                AVCaptureVideoPreviewLayer *camfeed = (AVCaptureVideoPreviewLayer *)self.camfeed.layer;
                
                camfeed.connection.videoOrientation = initialVideoOrientation;
                camfeed.videoGravity =  AVLayerVideoGravityResizeAspectFill;
            } );
        }
        else {
            NSLog( @"Could not add video device input to the session" );
            self.setupResult = AVCamSetupResultSessionConfigurationFailed;
        }
        
        AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
        AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];
        
        if ( ! audioDeviceInput ) {
            NSLog( @"Could not create audio device input: %@", error );
        }
        
        if ( [self.session canAddInput:audioDeviceInput] ) {
            [self.session addInput:audioDeviceInput];
        }
        else {
            NSLog( @"Could not add audio device input to the session" );
        }
        
        AVCaptureMovieFileOutput *movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
        if ( [self.session canAddOutput:movieFileOutput] ) {
            [self.session addOutput:movieFileOutput];
            AVCaptureConnection *connection = [movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
            if ( connection.isVideoStabilizationSupported ) {
                connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
            }
            self.movieFileOutput = movieFileOutput;
        }
        else {
            NSLog( @"Could not add movie file output to the session" );
            self.setupResult = AVCamSetupResultSessionConfigurationFailed;
        }
        
        AVCaptureStillImageOutput *stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
        if ( [self.session canAddOutput:stillImageOutput] ) {
            stillImageOutput.outputSettings = @{AVVideoCodecKey : AVVideoCodecJPEG};
            [self.session addOutput:stillImageOutput];
            self.stillImageOutput = stillImageOutput;
        }
        else {
            NSLog( @"Could not add still image output to the session" );
            self.setupResult = AVCamSetupResultSessionConfigurationFailed;
        }
        
        [self.session commitConfiguration];
    } );
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationNone];

    dispatch_async( self.sessionQueue, ^{
        switch ( self.setupResult )
        {
            case AVCamSetupResultSuccess:
            {
                // Only setup observers and start the session running if setup succeeded.
                [self addObservers];
                [self.session startRunning];
                self.sessionRunning = self.session.isRunning;
                
                break;
            }
            case AVCamSetupResultCameraNotAuthorized:
            {
                dispatch_async( dispatch_get_main_queue(), ^{
                    NSString *message = NSLocalizedString( @"AVCam doesn't have permission to use the camera, please change privacy settings", @"Alert message when the user has denied access to the camera" );
                    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVCam" message:message preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"OK", @"Alert OK button" ) style:UIAlertActionStyleCancel handler:nil];
                    [alertController addAction:cancelAction];
                    // Provide quick access to Settings.
                    UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"Settings", @"Alert button to open Settings" ) style:UIAlertActionStyleDefault handler:^( UIAlertAction *action ) {
                        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
                    }];
                    [alertController addAction:settingsAction];
                    [self presentViewController:alertController animated:YES completion:nil];
                } );
                break;
            }
            case AVCamSetupResultSessionConfigurationFailed:
            {
                dispatch_async( dispatch_get_main_queue(), ^{
                    NSString *message = NSLocalizedString( @"Unable to capture media", @"Alert message when something goes wrong during capture session configuration" );
                    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVCam" message:message preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"OK", @"Alert OK button" ) style:UIAlertActionStyleCancel handler:nil];
                    [alertController addAction:cancelAction];
                    [self presentViewController:alertController animated:YES completion:nil];
                } );
                break;
            }
        }
    } );
}

- (void)viewDidAppear:(BOOL)animated{
[super viewDidAppear:animated];
     //view.CameraFeed = CGAffineTransformMakeScale(1.0, 1.03);
#define kAppHasRunBeforeKey @"appFirstTimeRun"
if (![[[NSUserDefaults standardUserDefaults] valueForKey:kAppHasRunBeforeKey] boolValue]) {
    //put your welcome code here
    UIAlertController* intro = [UIAlertController alertControllerWithTitle:@"Welcome!"
                                                                   message:@"One Finger Tap: Focus \n Two Finger Tap: Record Video \n Three Finger Tap: Take Picture \n Shake to Show this Message Again!"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"Got it!" style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * action) {}];
    
    [intro addAction:defaultAction];
    [self presentViewController:intro animated:YES completion:nil];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kAppHasRunBeforeKey];
}
    
    
}


- (void)viewDidDisappear:(BOOL)animated
{
    dispatch_async( self.sessionQueue, ^{
        if ( self.setupResult == AVCamSetupResultSuccess ) {
            [self.session stopRunning];
            [self removeObservers];
        }
    } );
    
    [super viewDidDisappear:animated];
}

#pragma mark Orientation

- (BOOL)shouldAutorotate
{
    // Disable autorotation of the interface when recording is in progress.
    return ! self.movieFileOutput.isRecording;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    // Note that the app delegate controls the device orientation notifications required to use the device orientation.
    UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
    if ( UIDeviceOrientationIsPortrait( deviceOrientation ) || UIDeviceOrientationIsLandscape( deviceOrientation ) ) {
        AVCaptureVideoPreviewLayer *camfeed = (AVCaptureVideoPreviewLayer *)self.camfeed.layer;
        camfeed.connection.videoOrientation = (AVCaptureVideoOrientation)deviceOrientation;
    }
}

#pragma mark KVO and Notifications

- (void)addObservers
{
    [self.session addObserver:self forKeyPath:@"running" options:NSKeyValueObservingOptionNew context:SessionRunningContext];
    [self.stillImageOutput addObserver:self forKeyPath:@"capturingStillImage" options:NSKeyValueObservingOptionNew context:CapturingStillImageContext];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:self.videoDeviceInput.device];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:self.session];
    // A session can only run when the app is full screen. It will be interrupted in a multi-app layout, introduced in iOS 9,
    // see also the documentation of AVCaptureSessionInterruptionReason. Add observers to handle these session interruptions
    // and show a preview is paused message. See the documentation of AVCaptureSessionWasInterruptedNotification for other
    // interruption reasons.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionWasInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:self.session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionInterruptionEnded:) name:AVCaptureSessionInterruptionEndedNotification object:self.session];
}

- (void)removeObservers
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [self.session removeObserver:self forKeyPath:@"running" context:SessionRunningContext];
    [self.stillImageOutput removeObserver:self forKeyPath:@"capturingStillImage" context:CapturingStillImageContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ( context == CapturingStillImageContext ) {
        BOOL isCapturingStillImage = [change[NSKeyValueChangeNewKey] boolValue];
        
        if ( isCapturingStillImage ) {
            dispatch_async( dispatch_get_main_queue(), ^{
                self.camfeed.layer.opacity = 0.0;
                [UIView animateWithDuration:0.25 animations:^{
                    self.camfeed.layer.opacity = 1.0;
                }];
            } );
        }
    }
    else if ( context == SessionRunningContext ) {
        BOOL isSessionRunning = [change[NSKeyValueChangeNewKey] boolValue];
        
        dispatch_async( dispatch_get_main_queue(), ^{
            // Only enable the ability to change camera if the device has more than one camera.
            			self.recordButton.enabled = isSessionRunning;
        } );
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)subjectAreaDidChange:(NSNotification *)notification
{
    CGPoint devicePoint = CGPointMake( 0.5, 0.5 );
    [self focusWithMode:AVCaptureFocusModeContinuousAutoFocus exposeWithMode:AVCaptureExposureModeContinuousAutoExposure atDevicePoint:devicePoint monitorSubjectAreaChange:NO];
}

- (void)sessionRuntimeError:(NSNotification *)notification
{
    NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
    NSLog( @"Capture session runtime error: %@", error );
    
    // Automatically try to restart the session running if media services were reset and the last start running succeeded.
    // Otherwise, enable the user to try to resume the session running.
    if ( error.code == AVErrorMediaServicesWereReset ) {
        dispatch_async( self.sessionQueue, ^{
            if ( self.isSessionRunning ) {
                [self.session startRunning];
                self.sessionRunning = self.session.isRunning;
            }
            else {
                dispatch_async( dispatch_get_main_queue(), ^{
                   
                } );
            }
        } );
    }
    else {
        
    }
}

- (void)sessionWasInterrupted:(NSNotification *)notification
{
    // In some scenarios we want to enable the user to resume the session running.
    // For example, if music playback is initiated via control center while using AVCam,
    // then the user can let AVCam resume the session running, which will stop music playback.
    // Note that stopping music playback in control center will not automatically resume the session running.
    // Also note that it is not always possible to resume, see -[resumeInterruptedSession:].
    BOOL showResumeButton = NO;
    
    // In iOS 9 and later, the userInfo dictionary contains information on why the session was interrupted.
    if ( &AVCaptureSessionInterruptionReasonKey ) {
        AVCaptureSessionInterruptionReason reason = [notification.userInfo[AVCaptureSessionInterruptionReasonKey] integerValue];
        NSLog( @"Capture session was interrupted with reason %ld", (long)reason );
        
        if ( reason == AVCaptureSessionInterruptionReasonAudioDeviceInUseByAnotherClient ||
            reason == AVCaptureSessionInterruptionReasonVideoDeviceInUseByAnotherClient ) {
            showResumeButton = YES;
        }
        else if ( reason == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableWithMultipleForegroundApps ) {
            // Simply fade-in a label to inform the user that the camera is unavailable.
                [UIView animateWithDuration:0.25 animations:^{
        
            }];
        }
    }
    else {
        NSLog( @"Capture session was interrupted" );
        showResumeButton = ( [UIApplication sharedApplication].applicationState == UIApplicationStateInactive );
    }
    
    if ( showResumeButton ) {
        // Simply fade-in a button to enable the user to try to resume the session running.

        [UIView animateWithDuration:0.25 animations:^{

        }];
    }
}

- (void)sessionInterruptionEnded:(NSNotification *)notification
{
    NSLog( @"Capture session interruption ended" );
    

}



#pragma mark Actions

- (IBAction)resumeInterruptedSession:(id)sender
{
    dispatch_async( self.sessionQueue, ^{
        // The session might fail to start running, e.g., if a phone or FaceTime call is still using audio or video.
        // A failure to start the session running will be communicated via a session runtime error notification.
        // To avoid repeatedly failing to start the session running, we only try to restart the session running in the
        // session runtime error handler if we aren't trying to resume the session running.
        [self.session startRunning];
        self.sessionRunning = self.session.isRunning;
        if ( ! self.session.isRunning ) {
            dispatch_async( dispatch_get_main_queue(), ^{
                NSString *message = NSLocalizedString( @"Unable to resume", @"Alert message when unable to resume the session running" );
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVCam" message:message preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"OK", @"Alert OK button" ) style:UIAlertActionStyleCancel handler:nil];
                [alertController addAction:cancelAction];
                [self presentViewController:alertController animated:YES completion:nil];
            } );
        }
        else {
            dispatch_async( dispatch_get_main_queue(), ^{
               
            } );
        }
    } );
}

- (void)toggleMovieRecording:(id)sender
{
    [self pulseRecordButton];
    self.recordButton.hidden = YES;
    // Disable the Camera button until recording finishes, and disable the Record button until recording starts or finishes. See the
    // AVCaptureFileOutputRecordingDelegate methods.
    self.recordButton.enabled = NO;
  //  self.recordButton.hidden = NO;

    dispatch_async( self.sessionQueue, ^{
       
        if ( ! self.movieFileOutput.isRecording ) {
            if ( [UIDevice currentDevice].isMultitaskingSupported ) {
                // Setup background task. This is needed because the -[captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:]
                // callback is not received until AVCam returns to the foreground unless you request background execution time.
                // This also ensures that there will be time to write the file to the photo library when AVCam is backgrounded.
                // To conclude this background execution, -endBackgroundTask is called in
                // -[captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:] after the recorded file has been saved.
                self.backgroundRecordingID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:nil];
            }
            
            // Update the orientation on the movie file output video connection before starting recording.
            AVCaptureConnection *connection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
            AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.camfeed.layer;
            connection.videoOrientation = previewLayer.connection.videoOrientation;
            
            // Turn OFF flash for video recording.
            [ViewController setFlashMode:AVCaptureFlashModeOff forDevice:self.videoDeviceInput.device];
            
            // Start recording to a temporary file.
            NSString *outputFileName = [NSProcessInfo processInfo].globallyUniqueString;
            NSString *outputFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[outputFileName stringByAppendingPathExtension:@"mov"]];
            [self.movieFileOutput startRecordingToOutputFileURL:[NSURL fileURLWithPath:outputFilePath] recordingDelegate:self];
        }
        else {
            [self.movieFileOutput stopRecording];
            self.recordButton.hidden = YES;
        }
    } );
}

- (IBAction)changeCamera:(id)sender
{
    self.recordButton.enabled = NO;
    
    dispatch_async( self.sessionQueue, ^{
        AVCaptureDevice *currentVideoDevice = self.videoDeviceInput.device;
        AVCaptureDevicePosition preferredPosition = AVCaptureDevicePositionUnspecified;
        AVCaptureDevicePosition currentPosition = currentVideoDevice.position;
        
        switch ( currentPosition )
        {
            case AVCaptureDevicePositionUnspecified:
            case AVCaptureDevicePositionFront:
                preferredPosition = AVCaptureDevicePositionBack;
                break;
            case AVCaptureDevicePositionBack:
                preferredPosition = AVCaptureDevicePositionFront;
                break;
        }
        
        AVCaptureDevice *videoDevice = [ViewController deviceWithMediaType:AVMediaTypeVideo preferringPosition:preferredPosition];
        AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
        
        [self.session beginConfiguration];
        
        // Remove the existing device input first, since using the front and back camera simultaneously is not supported.
        [self.session removeInput:self.videoDeviceInput];
        
        if ( [self.session canAddInput:videoDeviceInput] ) {
            [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:currentVideoDevice];
            
            [ViewController setFlashMode:AVCaptureFlashModeAuto forDevice:videoDevice];
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:videoDevice];
            
            [self.session addInput:videoDeviceInput];
            self.videoDeviceInput = videoDeviceInput;
        }
        else {
            [self.session addInput:self.videoDeviceInput];
        }
        
        AVCaptureConnection *connection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
        if ( connection.isVideoStabilizationSupported ) {
            connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
        }
        
        [self.session commitConfiguration];
        
        dispatch_async( dispatch_get_main_queue(), ^{
            self.recordButton.enabled = YES;

        } );
    } );
}

- (void)snapStillImage:(id)sender
{
    dispatch_async( self.sessionQueue, ^{
        AVCaptureConnection *connection = [self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo];
        AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.camfeed.layer;
        
        // Update the orientation on the still image output video connection before capturing.
        connection.videoOrientation = previewLayer.connection.videoOrientation;
        
        // Flash set to Auto for Still Capture.
        [ViewController setFlashMode:AVCaptureFlashModeAuto forDevice:self.videoDeviceInput.device];
        
        // Capture a still image.
        [self.stillImageOutput captureStillImageAsynchronouslyFromConnection:connection completionHandler:^( CMSampleBufferRef imageDataSampleBuffer, NSError *error ) {
            if ( imageDataSampleBuffer ) {
                // The sample buffer is not retained. Create image data before saving the still image to the photo library asynchronously.
                NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
                [PHPhotoLibrary requestAuthorization:^( PHAuthorizationStatus status ) {
                    if ( status == PHAuthorizationStatusAuthorized ) {
                        // To preserve the metadata, we create an asset from the JPEG NSData representation.
                        // Note that creating an asset from a UIImage discards the metadata.
                        // In iOS 9, we can use -[PHAssetCreationRequest addResourceWithType:data:options].
                        // In iOS 8, we save the image to a temporary file and use +[PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:].
                        if ( [PHAssetCreationRequest class] ) {
                            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                                [[PHAssetCreationRequest creationRequestForAsset] addResourceWithType:PHAssetResourceTypePhoto data:imageData options:nil];
                            } completionHandler:^( BOOL success, NSError *error ) {
                                if ( ! success ) {
                                    NSLog( @"Error occurred while saving image to photo library: %@", error );
                                }
                            }];
                        }
                        else {
                            NSString *temporaryFileName = [NSProcessInfo processInfo].globallyUniqueString;
                            NSString *temporaryFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[temporaryFileName stringByAppendingPathExtension:@"jpg"]];
                            NSURL *temporaryFileURL = [NSURL fileURLWithPath:temporaryFilePath];
                            
                            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                                NSError *error = nil;
                                [imageData writeToURL:temporaryFileURL options:NSDataWritingAtomic error:&error];
                                if ( error ) {
                                    NSLog( @"Error occured while writing image data to a temporary file: %@", error );
                                }
                                else {
                                    [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:temporaryFileURL];
                                }
                            } completionHandler:^( BOOL success, NSError *error ) {
                                if ( ! success ) {
                                    NSLog( @"Error occurred while saving image to photo library: %@", error );
                                }
                                
                                // Delete the temporary file.
                                [[NSFileManager defaultManager] removeItemAtURL:temporaryFileURL error:nil];
                            }];
                        }
                    }
                }];
            }
            else {
                NSLog( @"Could not capture still image: %@", error );
            }
        }];
    } );
}

- (IBAction)focusAndExposeTap:(UIGestureRecognizer *)gestureRecognizer
{
    CGPoint devicePoint = [(AVCaptureVideoPreviewLayer *)self.camfeed.layer captureDevicePointOfInterestForPoint:[gestureRecognizer locationInView:gestureRecognizer.view]];
    [self focusWithMode:AVCaptureFocusModeAutoFocus exposeWithMode:AVCaptureExposureModeAutoExpose atDevicePoint:devicePoint monitorSubjectAreaChange:YES];
}

#pragma mark File Output Recording Delegate

- (void)pulseRecordButton {
    
    /*
    [UIView animateWithDuration:2.0
                          delay:1.0
                        options:UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat | UIViewAnimationOptionCurveEaseInOut
                     animations:^{
                         // do whatever animation you want, e.g.,
                         [UIView animateWithDuration:2.0 animations:^{self.recordButton.alpha = 1.0;}];
                         [UIView animateWithDuration:0.5 animations:^{self.recordButton.alpha = 0.0;}];
                         
                         
                        // ViewController.frame = Frame1;
                     }
                     completion:NULL];
    
    
    [UIView animateWithDuration:2.0 animations:^{self.recordButton.alpha = 1.0;}];
    [UIView animateWithDuration:2.0 animations:^{self.recordButton.alpha = 0.0;}];
    */
    //[self.recordButton setAlpha:0.0f];
    
    //fade in
//    [UIView animateWithDuration:2.0f animations:^{
        
//        [self.recordButton setAlpha:1.0f];
        
//    } completion:^(BOOL finished) {
        
        //fade out
//        [UIView animateWithDuration:2.0f animations:^{
            
//            [self.recordButton setAlpha:0.0f];
            
//        } completion:nil];
        
//    }];
    self.recordButton.alpha = 1.0;
    [UIView animateWithDuration:.75
                          delay:.75
                        options:UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat
                     animations:^{
                         self.recordButton.alpha = 0.0;
                         //fade in here (changing alpha of UILabel component)
                     }
                     completion:^(BOOL finished){
                
    
                         
                             //start a fade out here when previous animation is finished (changing alpha of UILabel component)
                         
                     
                         if ((self.recordButton.hidden = NO)) {
                             [UIView setAnimationRepeatCount: 10];
                             //printf("I made it");
                         }
                         if ((self.recordButton.hidden = YES)) {
                             [UIView setAnimationRepeatCount: 10];
                             //printf("I didn't make it");
                             //self.recordButton.alpha = 0.0;
                         }
                     
                     
                         
                     }];
                     }
    
/*
    CABasicAnimation *pulseAnimation = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    pulseAnimation.duration = .5;
    pulseAnimation.toValue = [NSNumber numberWithFloat:1.1];
    pulseAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    pulseAnimation.autoreverses = YES;
    pulseAnimation.repeatCount = FLT_MAX;
    [[recordButton layer] addAnimation:pulseAnimation forKey:nil];
 */


- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (motion == UIEventSubtypeMotionShake)
    {
        // User was shaking the device. Post a notification named "shake."
        [self instructionAlertBox:nil];
    }
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
    // Enable the Record button to let the user stop the recording.
    dispatch_async( dispatch_get_main_queue(), ^{
        self.recordButton.enabled = YES;
   //     [self.recordButton setTitle:NSLocalizedString( @"Stop", @"Recording button stop title") forState:UIControlStateNormal];
        self.recordButton.hidden = NO;
    });
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
    // Note that currentBackgroundRecordingID is used to end the background task associated with this recording.
    // This allows a new recording to be started, associated with a new UIBackgroundTaskIdentifier, once the movie file output's isRecording property
    // is back to NO — which happens sometime after this method returns.
    // Note: Since we use a unique file path for each recording, a new recording will not overwrite a recording currently being saved.
    UIBackgroundTaskIdentifier currentBackgroundRecordingID = self.backgroundRecordingID;
    self.backgroundRecordingID = UIBackgroundTaskInvalid;
    
    dispatch_block_t cleanup = ^{
        [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
        if ( currentBackgroundRecordingID != UIBackgroundTaskInvalid ) {
            [[UIApplication sharedApplication] endBackgroundTask:currentBackgroundRecordingID];
        }
    };
    
    BOOL success = YES;
    
    if ( error ) {
        NSLog( @"Movie file finishing error: %@", error );
        success = [error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] boolValue];
    }
    if ( success ) {
        // Check authorization status.
        [PHPhotoLibrary requestAuthorization:^( PHAuthorizationStatus status ) {
            if ( status == PHAuthorizationStatusAuthorized ) {
                // Save the movie file to the photo library and cleanup.
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    // In iOS 9 and later, it's possible to move the file into the photo library without duplicating the file data.
                    // This avoids using double the disk space during save, which can make a difference on devices with limited free disk space.
                    if ( [PHAssetResourceCreationOptions class] ) {
                        PHAssetResourceCreationOptions *options = [[PHAssetResourceCreationOptions alloc] init];
                        options.shouldMoveFile = YES;
                        PHAssetCreationRequest *changeRequest = [PHAssetCreationRequest creationRequestForAsset];
                        [changeRequest addResourceWithType:PHAssetResourceTypeVideo fileURL:outputFileURL options:options];
                    }
                    else {
                        [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:outputFileURL];
                    }
                } completionHandler:^( BOOL success, NSError *error ) {
                    if ( ! success ) {
                        NSLog( @"Could not save movie to photo library: %@", error );
                    }
                    cleanup();
                }];
            }
            else {
                cleanup();
            }
        }];
    }
    else {
        cleanup();
    }
    
    // Enable the Camera and Record buttons to let the user switch camera and start another recording.
    dispatch_async( dispatch_get_main_queue(), ^{
        // Only enable the ability to change camera if the device has more than one camera.
        self.recordButton.enabled = YES;
        self.recordButton.hidden = YES;
   //     [self.recordButton setTitle:NSLocalizedString( @"Record", @"Recording button record title" ) forState:UIControlStateNormal];
       self.recordButton.hidden = YES;

    });
}

#pragma mark Device Configuration

- (void)focusWithMode:(AVCaptureFocusMode)focusMode exposeWithMode:(AVCaptureExposureMode)exposureMode atDevicePoint:(CGPoint)point monitorSubjectAreaChange:(BOOL)monitorSubjectAreaChange
{
    dispatch_async( self.sessionQueue, ^{
        AVCaptureDevice *device = self.videoDeviceInput.device;
        NSError *error = nil;
        if ( [device lockForConfiguration:&error] ) {
            // Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
            // Call -set(Focus/Exposure)Mode: to apply the new point of interest.
            if ( device.isFocusPointOfInterestSupported && [device isFocusModeSupported:focusMode] ) {
                device.focusPointOfInterest = point;
                device.focusMode = focusMode;
            }
            
            if ( device.isExposurePointOfInterestSupported && [device isExposureModeSupported:exposureMode] ) {
                device.exposurePointOfInterest = point;
                device.exposureMode = exposureMode;
            }
            
            device.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange;
            [device unlockForConfiguration];
        }
        else {
            NSLog( @"Could not lock device for configuration: %@", error );
        }
    } );
}

+ (void)setFlashMode:(AVCaptureFlashMode)flashMode forDevice:(AVCaptureDevice *)device
{
    if ( device.hasFlash && [device isFlashModeSupported:flashMode] ) {
        NSError *error = nil;
        if ( [device lockForConfiguration:&error] ) {
            device.flashMode = flashMode;
            [device unlockForConfiguration];
        }
        else {
            NSLog( @"Could not lock device for configuration: %@", error );
        }
    }
}

+ (AVCaptureDevice *)deviceWithMediaType:(NSString *)mediaType preferringPosition:(AVCaptureDevicePosition)position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
    AVCaptureDevice *captureDevice = devices.firstObject;
    
    for ( AVCaptureDevice *device in devices ) {
        if ( device.position == position ) {
            captureDevice = device;
            break;
        }
    }
    
    return captureDevice;
}
- (void) instructionAlertBox:(id)sender {
    //alertbox for instructions
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Instructions"
                                                                   message:@"One Finger Tap: Focus \n Two Finger Tap: Record Video \n Three Finger Tap: Take Picture"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"Got it!" style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * action) {}];
    
    [alert addAction:defaultAction];
    [self presentViewController:alert animated:YES completion:nil];
    //
}

- (void) viewWasThreeFingerTapped:(id)sender {
    // [self instructionAlertBox:nil];
    [self snapStillImage:nil];
    // Flash the screen white and fade it out
    UIView *flashView = [[UIView alloc] initWithFrame:[[self camfeed] frame]];
    [flashView setBackgroundColor:[UIColor whiteColor]];
    [[[self view] window] addSubview:flashView];
    
    [UIView animateWithDuration:1.f
                     animations:^{
                         [flashView setAlpha:0.f];
                     }
                     completion:^(BOOL finished){
                         [flashView removeFromSuperview];
                     }
     ];

}

- (void) viewWasTwoFingerTapped:(id)sender {

   [self toggleMovieRecording:nil];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
