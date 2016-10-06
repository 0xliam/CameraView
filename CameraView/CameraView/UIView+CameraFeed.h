//
//  UIView+CameraFeed.h
//  CameraView
//
//  Created by Liam Patterson on 9/28/15.
//  Copyright © 2015 Liam Patterson. All rights reserved.
//

#import <UIKit/UIKit.h>

@import UIKit;

@class AVCaptureSession;

@interface CameraFeed : UIView

@property (nonatomic) AVCaptureSession *session;

@end
