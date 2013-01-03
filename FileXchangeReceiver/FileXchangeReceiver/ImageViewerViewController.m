//
//  ImageViewerViewController.m
//  FileXchangeReceiver
//
//  Created by Brian Gerfort on 19/10/12.
//  Copyright (c) 2012 2ndNature. All rights reserved.
//

#import "ImageViewerViewController.h"

@interface ImageViewerViewController ()

@end

@implementation ImageViewerViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    UIImageView *imgV = [[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:_imageFilename]];
    [imgV setBackgroundColor:[UIColor blackColor]];
    [imgV setContentMode:UIViewContentModeScaleAspectFit];
	self.view = imgV;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)setImageFilename:(NSString *)filePath
{
    _imageFilename = filePath;
    [(UIImageView *)self.view setImage:[UIImage imageWithContentsOfFile:filePath]];
    [self setTitle:([filePath length] > 0) ? [filePath lastPathComponent] : @""];
}

@end
