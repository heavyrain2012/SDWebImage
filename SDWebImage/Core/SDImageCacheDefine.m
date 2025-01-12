/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDImageCacheDefine.h"
#import "SDImageCodersManager.h"
#import "SDImageCoderHelper.h"
#import "SDAnimatedImage.h"
#import "UIImage+Metadata.h"
#import "SDInternalMacros.h"

static NSArray<NSString *>* GetKnownContextOptions(void) {
    static NSArray<NSString *> *knownContextOptions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        knownContextOptions =
        [NSArray arrayWithObjects:
         SDWebImageContextSetImageOperationKey,
         SDWebImageContextCustomManager,
         SDWebImageContextImageCache,
         SDWebImageContextImageLoader,
         SDWebImageContextImageCoder,
         SDWebImageContextImageTransformer,
         SDWebImageContextImageScaleFactor,
         SDWebImageContextImagePreserveAspectRatio,
         SDWebImageContextImageThumbnailPixelSize,
         SDWebImageContextQueryCacheType,
         SDWebImageContextStoreCacheType,
         SDWebImageContextOriginalQueryCacheType,
         SDWebImageContextOriginalStoreCacheType,
         SDWebImageContextOriginalImageCache,
         SDWebImageContextAnimatedImageClass,
         SDWebImageContextDownloadRequestModifier,
         SDWebImageContextDownloadResponseModifier,
         SDWebImageContextDownloadDecryptor,
         SDWebImageContextCacheKeyFilter,
         SDWebImageContextCacheSerializer
         , nil];
    });
    return knownContextOptions;
}

SDImageCoderOptions * _Nonnull SDGetDecodeOptionsFromContext(SDWebImageContext * _Nullable context, SDWebImageOptions options, NSString * _Nonnull cacheKey) {
    BOOL decodeFirstFrame = SD_OPTIONS_CONTAINS(options, SDWebImageDecodeFirstFrameOnly);
    NSNumber *scaleValue = context[SDWebImageContextImageScaleFactor];
    CGFloat scale = scaleValue.doubleValue >= 1 ? scaleValue.doubleValue : SDImageScaleFactorForKey(cacheKey);
    NSNumber *preserveAspectRatioValue = context[SDWebImageContextImagePreserveAspectRatio];
    NSValue *thumbnailSizeValue;
    BOOL shouldScaleDown = SD_OPTIONS_CONTAINS(options, SDWebImageScaleDownLargeImages);
    if (shouldScaleDown) {
        CGFloat thumbnailPixels = SDImageCoderHelper.defaultScaleDownLimitBytes / 4;
        CGFloat dimension = ceil(sqrt(thumbnailPixels));
        thumbnailSizeValue = @(CGSizeMake(dimension, dimension));
    }
    if (context[SDWebImageContextImageThumbnailPixelSize]) {
        thumbnailSizeValue = context[SDWebImageContextImageThumbnailPixelSize];
    }
    NSString *typeIdentifierHint = context[SDWebImageContextImageTypeIdentifierHint];
    NSString *fileExtensionHint = cacheKey.pathExtension; // without dot
    
    SDImageCoderMutableOptions *mutableCoderOptions = [NSMutableDictionary dictionaryWithCapacity:6];
    mutableCoderOptions[SDImageCoderDecodeFirstFrameOnly] = @(decodeFirstFrame);
    mutableCoderOptions[SDImageCoderDecodeScaleFactor] = @(scale);
    mutableCoderOptions[SDImageCoderDecodePreserveAspectRatio] = preserveAspectRatioValue;
    mutableCoderOptions[SDImageCoderDecodeThumbnailPixelSize] = thumbnailSizeValue;
    mutableCoderOptions[SDImageCoderDecodeTypeIdentifierHint] = typeIdentifierHint;
    mutableCoderOptions[SDImageCoderDecodeFileExtensionHint] = fileExtensionHint;
    // Hack to remove all known context options before SDWebImage 5.14.0
    SDImageCoderMutableOptions *mutableContext = [NSMutableDictionary dictionaryWithDictionary:context];
    [mutableContext removeObjectsForKeys:GetKnownContextOptions()];
    mutableCoderOptions[SDImageCoderWebImageContext] = [mutableContext copy];
    SDImageCoderOptions *coderOptions = [mutableCoderOptions copy];
    
    return coderOptions;
}

UIImage * _Nullable SDImageCacheDecodeImageData(NSData * _Nonnull imageData, NSString * _Nonnull cacheKey, SDWebImageOptions options, SDWebImageContext * _Nullable context) {
    NSCParameterAssert(imageData);
    NSCParameterAssert(cacheKey);
    UIImage *image;
    SDImageCoderOptions *coderOptions = SDGetDecodeOptionsFromContext(context, options, cacheKey);
    BOOL decodeFirstFrame = SD_OPTIONS_CONTAINS(options, SDWebImageDecodeFirstFrameOnly);
    CGFloat scale = [coderOptions[SDImageCoderDecodeScaleFactor] doubleValue];
    
    // Grab the image coder
    id<SDImageCoder> imageCoder;
    if ([context[SDWebImageContextImageCoder] conformsToProtocol:@protocol(SDImageCoder)]) {
        imageCoder = context[SDWebImageContextImageCoder];
    } else {
        imageCoder = [SDImageCodersManager sharedManager];
    }
    
    if (!decodeFirstFrame) {
        Class animatedImageClass = context[SDWebImageContextAnimatedImageClass];
        // check whether we should use `SDAnimatedImage`
        if ([animatedImageClass isSubclassOfClass:[UIImage class]] && [animatedImageClass conformsToProtocol:@protocol(SDAnimatedImage)]) {
            image = [[animatedImageClass alloc] initWithData:imageData scale:scale options:coderOptions];
            if (image) {
                // Preload frames if supported
                if (options & SDWebImagePreloadAllFrames && [image respondsToSelector:@selector(preloadAllFrames)]) {
                    [((id<SDAnimatedImage>)image) preloadAllFrames];
                }
            } else {
                // Check image class matching
                if (options & SDWebImageMatchAnimatedImageClass) {
                    return nil;
                }
            }
        }
    }
    if (!image) {
        image = [imageCoder decodedImageWithData:imageData options:coderOptions];
    }
    if (image) {
        BOOL shouldDecode = !SD_OPTIONS_CONTAINS(options, SDWebImageAvoidDecodeImage);
        if ([image.class conformsToProtocol:@protocol(SDAnimatedImage)]) {
            // `SDAnimatedImage` do not decode
            shouldDecode = NO;
        } else if (image.sd_isAnimated) {
            // animated image do not decode
            shouldDecode = NO;
        }
        if (shouldDecode) {
            image = [SDImageCoderHelper decodedImageWithImage:image];
        }
        // assign the decode options, to let manager check whether to re-decode if needed
        image.sd_decodeOptions = coderOptions;
    }
    
    return image;
}
