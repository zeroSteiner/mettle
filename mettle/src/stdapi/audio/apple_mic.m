#import <AVFoundation/AVFoundation.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIImage.h>
#else
#import <AppKit/NSImage.h>
#endif

#include "tlv.h"
#include "mic.h"

#define TLV_TYPE_AUDIO_DURATION  (TLV_META_TYPE_UINT  | TLV_EXTENSIONS + 1)
#define TLV_TYPE_AUDIO_DATA  (TLV_META_TYPE_RAW  | TLV_EXTENSIONS + 2)
#define TLV_TYPE_AUDIO_INTERFACE_NAME  (TLV_META_TYPE_UINT  | TLV_EXTENSIONS + 3)
#define TLV_TYPE_AUDIO_INTERFACE_FULLNAME  (TLV_META_TYPE_STRING  | TLV_EXTENSIONS + 4)

@interface AudioCapture : NSObject <AVCaptureAudioDataOutputSampleBufferDelegate>
- (void) captureOutput: (AVCaptureOutput*) output
 didOutputSampleBuffer: (CMSampleBufferRef) buffer
        fromConnection: (AVCaptureConnection*) connection;
@end
@interface AudioCapture ()
{
    AVCaptureSession* session;
    unsigned char* audioData;
    unsigned int audioDataDownsampleStep;
    unsigned int audioDataBitsPerChannel;
    int length;
}
- (BOOL) start: (int) deviceIndex;
- (void) stop;
- (NSData *) getFrame;
@end

@implementation AudioCapture

- (id) init
{
    self = [super init];
    length = 0;
    audioData = (unsigned char*)malloc(32000);
    audioDataDownsampleStep = 16;
    audioDataBitsPerChannel= 16;
    return self;
}

- (void) dealloc
{
    @synchronized (self) {
        
    }
}

- (BOOL) start: (int) deviceIndex
{
    session = [[AVCaptureSession alloc] init];
    [session setSessionPreset:AVCaptureSessionPresetLow];

    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio];
    AVCaptureDevice *device = devices[deviceIndex];

    [device lockForConfiguration:nil];

    NSLog(@"Device Formats: %@", [device formats]);

    //device.activeFormat = device.formats[7];

    NSLog(@"Device activeformats: %@", [device activeFormat]);
    //NSLog(@"Device supports session preset: %@", [device formats]);
    const AudioStreamBasicDescription *ASBD = CMAudioFormatDescriptionGetStreamBasicDescription(device.activeFormat.formatDescription);
    NSLog(@"ASBD samplerate: %f", ASBD->mSampleRate);
    NSLog(@"ASBD bitsperchannel: %u", ASBD->mBitsPerChannel);
    NSLog(@"ASBD channelsperframe: %u", ASBD->mChannelsPerFrame);
    audioDataDownsampleStep = ((unsigned int)(ASBD->mSampleRate) / 11025) * (ASBD->mBitsPerChannel / 8) * ASBD->mChannelsPerFrame;
    audioDataBitsPerChannel = ASBD->mBitsPerChannel;
    NSLog(@"downsamplestep: %u", audioDataDownsampleStep);
    NSLog(@"downsamplebitsperchannel: %u", audioDataBitsPerChannel);
    
    NSError* error = nil;
    
    AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice: device  error: &error];
    [session addInput:input];
    
    NSLog(@"Input: %@", input);
    
    AVCaptureAudioDataOutput *output = [[AVCaptureAudioDataOutput alloc] init];
    [session addOutput:output];
    
    dispatch_queue_t queue = dispatch_queue_create("audio_interface_queue", NULL);
    [output setSampleBufferDelegate:self queue:queue];
    
    [session startRunning];
    return true;
}

- (void) stop
{
    [session stopRunning];
}

- (NSData* ) getFrame
{
    
    @synchronized (self) {
        NSData *audioPayload = [NSData dataWithBytes:audioData length:length];
        length = 0;
        return audioPayload;
    }
}

- (void) captureOutput: (AVCaptureOutput*) output
 didOutputSampleBuffer: (CMSampleBufferRef) buffer
        fromConnection: (AVCaptureConnection*) connection
{
    //NSLog(@"buffer in Capture: %@", buffer);
    
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(buffer);
    //NSLog(@"blockBuffer: %@", blockBuffer);
    
    NSLog(@"Writing length: %zu", CMBlockBufferGetDataLength(blockBuffer));
    
    @synchronized (self) {
        size_t bufferLen = CMBlockBufferGetDataLength(blockBuffer);
        CMBlockBufferCopyDataBytes(blockBuffer, 0, bufferLen, audioData);

        // Downsample the audio to 11.025KHz, 16-bit, single channel
int count = 0;
        size_t downsampledLen = 0;
        for (int i = 0; i < copyLen; i += audioDataDownsampleStep) {
if (count < 16){
NSLog(@"sample count %d: 0x%08x", count, *((uint32_t *)&audioDataBuf[i]));
}
            switch (audioDataBitsPerChannel) {
                case 32:
                    *((uint16_t *)&audioData[length]) = (uint16_t)(*((float *)&audioData[i]) * 32767);
                    break;
                case 24:
                    audioDataBuf[downsampledLen] = audioDataBuf[i+1];
                    audioDataBuf[downsampledLen+1] = audioDataBuf[i+2];
                    break;
                case 16:
                default:
                    audioData[length] = audioData[i];
                    audioData[length+1] = audioData[i+1];
                    break;
            }
if (count++ < 16){
NSLog(@"downsample sample count %d: 0x%04x", count, *((uint16_t *)&audioDataBuf[downsampledLen]));
}
            downsampledLen += 2;
        }
    }
}
@end

AudioCapture* capture;

struct tlv_packet *audio_mic_get_frame(struct tlv_handler_ctx *ctx)
{    
    struct tlv_packet *p = tlv_packet_response_result(ctx, TLV_RESULT_SUCCESS);
    @autoreleasepool {
NSLog(@"MSF is collecting the audio data now...");
        NSData* wavData = [capture getFrame];
        if (wavData) {
            //NSLog(@"wav: %@", wavData);
            p = tlv_packet_add_raw(p, TLV_TYPE_AUDIO_DATA, wavData.bytes, wavData.length);
        }else {
            p = tlv_packet_add_raw(p, TLV_TYPE_AUDIO_DATA, NULL, 0);
        }
    }
    return p;
}

struct tlv_packet *audio_mic_start(struct tlv_handler_ctx *ctx)
{
    uint32_t deviceIndex = 0;
    uint32_t quality = 0;
    tlv_packet_get_u32(ctx->req, TLV_TYPE_AUDIO_INTERFACE_NAME, &deviceIndex);
    tlv_packet_get_u32(ctx->req, TLV_TYPE_AUDIO_DURATION, &quality);
    int rc = TLV_RESULT_FAILURE;
    
    //make channel
//    struct mettle *m = ctx->arg;
//    struct channelmgr *cm = mettle_get_channelmgr(m);
    
//    struct process *p = process_create(pm, path, &opts);
//    if (p == NULL) {
//        return tlv_packet_response_result(ctx, TLV_RESULT_FAILURE);
//    }
    
    //struct channelmgr_ctx *cm_ctx = calloc(1, sizeof *ctx);
    //struct channel *c = channelmgr_channel_new(cm, "stream");
    //channel_set_ctx(c, p);
    //ctx->channel = c;
    //cm_ctx->cm = cm;
    //cm_ctx->channel_id = ctx->channel_id = channel_get_id(c);
    
//    process_set_callbacks(p,
//                          process_channel_read_cb,
//                          process_channel_read_cb,
//                          process_channel_exit_cb, cm_ctx);
    struct tlv_packet *p = tlv_packet_response_result(ctx, TLV_RESULT_SUCCESS);
    //p = tlv_packet_add_str(p, TLV_TYPE_CHANNEL_ID, channel_get_id(c));
    
    @autoreleasepool {
        capture = [[AudioCapture alloc] init];
        if ([capture start:deviceIndex]) {
            rc = TLV_RESULT_SUCCESS;
        } else {
            capture = nil;
        }
    }
    //return tlv_packet_response_result(ctx, rc);
    return p;
}

struct tlv_packet *audio_mic_stop(struct tlv_handler_ctx *ctx)
{
    @autoreleasepool {
        [capture stop];
    }
    return tlv_packet_response_result(ctx, TLV_RESULT_SUCCESS);
}

struct tlv_packet *audio_mic_list(struct tlv_handler_ctx *ctx)
{
    struct tlv_packet *p = tlv_packet_response_result(ctx, TLV_RESULT_SUCCESS);
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio];
    for (AVCaptureDevice *device in devices) {
        const char *webcam_str = (const char *)[[device uniqueID]cStringUsingEncoding:NSUTF8StringEncoding];
        p = tlv_packet_add_str(p, TLV_TYPE_AUDIO_INTERFACE_FULLNAME, webcam_str);
    }
    return p;
}

