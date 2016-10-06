//
//  UIView+CameraFeed.m
//  CameraView
//
//  Created by Liam Patterson on 9/28/15.
//  Copyright © 2015 Liam Patterson. All rights reserved.
//

@import AVFoundation;

#import "UIView+CameraFeed.h"

@implementation CameraFeed

+ (Class)layerClass
{
    return [AVCaptureVideoPreviewLayer class];
    
}

- (AVCaptureSession *)session
{
    AVCaptureVideoPreviewLayer *camfeed = (AVCaptureVideoPreviewLayer *)self.layer;
    return camfeed.session;
}
    
- (void)setSession: (AVCaptureSession *)session
    {
        AVCaptureVideoPreviewLayer *camfeed = (AVCaptureVideoPreviewLayer *)self.layer;
        camfeed.session = session;
        
    }

@end
