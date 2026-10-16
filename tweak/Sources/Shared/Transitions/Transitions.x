// SPDX-License-Identifier: MIT
// Transitions (Transitions.h): the entry of each new track softened on the render thread.
//
// The player's state is watched through Shared/Player/PlayerState (one hook for every feature, main thread).
// When the track URI changes while the player is playing, the observer arms a request: the host time of the
// change and a generation count, both atomics. The output processor, registered at SGAudioStageTransitions
// (after the effects, so a reverb tail or an EQ'd entry is shaped too, before music haptics listens), sees
// the new generation on its next render and starts a run of SGTransitionDSP.h over the first `length`
// frames: a dB-linear gain ramp from -12 dB and a low-pass opening from the softness's cutoff to 20 kHz. A
// request older than a second when the render thread gets to it (the output was not running) is dropped
// rather than shaping the middle of a song. A paused song resumed keeps its URI, so it is not touched.
//
// The parameters the main thread sets (length in frames at the output's rate, the start cutoff and gain)
// sit in two slots: a writer fills the slot not in use and publishes its index; the render thread copies the
// published slot once per render, and SGTransitionRunStart clamps whatever it reads, so a write landing in
// the same instant costs at worst one render of the old values. Only the hardware's float buffers are
// shaped (a buffer per channel or interleaved); an integer output leaves the sound alone and says so in the
// status. No outgoing fade: SGAudioPipelineSourcePrefix answers only inside a source pull, and an output
// stage is not in one, so the previous track's last frames cannot be told apart from the new one's first.
//
// Threading: the render callback touches atomics, the published slot and its own run. prepare runs on the
// thread Spotify starts its output on. The observer and the settings are main thread.
#import <AudioToolbox/AudioToolbox.h>
#import <mach/mach_time.h>
#import <stdatomic.h>
#import "Core/SGCore.h"
#import "Shared/Audio/SGAudioPipeline.h"
#import "Shared/Player/PlayerState.h"
#import "Transitions.h"
#import "SGTransitionDSP.h"

// A request the render thread first sees later than this is for an entry already gone by.
static const double kRequestLifetime = 1.0;
static const float kStartGainDb = -12;

typedef enum { SGOutputUnseen, SGOutputFloat, SGOutputUnsupported } SGOutputState;

#pragma mark - shared between the threads

static atomic_bool sg_enabled;
static atomic_int sg_outputState;
// The format of the buffers the notify gets, packed so the render thread never reads half of a change
// (flags in the low 32 bits, then channels, then bytes per sample).
static atomic_uint_fast64_t sg_layout;
static atomic_uint_fast64_t sg_rateBits;
// The parameters as one atomic word so the render thread can never read a torn struct: lengthFrames in
// the low 32 bits, the start cutoff in whole Hz above. The rate is read beside it from sg_rateBits; after
// a format change the two can be one render out of step, which only runs the ramp a fraction long.
static atomic_uint_fast64_t sg_paramsBits;
// The request: a generation the render thread compares with the last it served, and when it was made.
static atomic_uint sg_requestGeneration;
static atomic_uint_fast64_t sg_requestHostTime;
// Counters for the status line.
static atomic_uint sg_entriesShaped, sg_entriesDropped, sg_skippedRenders;
static double sg_secondsPerTick;

static void storeDouble(atomic_uint_fast64_t *slot, double value) {
    uint64_t bits;
    memcpy(&bits, &value, sizeof bits);
    atomic_store(slot, bits);
}

static double loadDouble(atomic_uint_fast64_t *slot) {
    uint64_t bits = atomic_load_explicit(slot, memory_order_relaxed);
    double value;
    memcpy(&value, &bits, sizeof value);
    return value;
}

#pragma mark - the render thread

static SGTransitionRun sg_run;
static unsigned sg_servedGeneration;

static OSStatus rendered(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp, UInt32 bus,
                         UInt32 frames, AudioBufferList *data) {
    if (!(*flags & kAudioUnitRenderAction_PostRender) || bus != 0 || !data || !data->mNumberBuffers || !frames) return noErr;
    if (!atomic_load_explicit(&sg_enabled, memory_order_relaxed)) {
        sg_run.position = sg_run.length; // a run in flight ends with the switch
        return noErr;
    }
    unsigned generation = atomic_load_explicit(&sg_requestGeneration, memory_order_acquire);
    if (generation != sg_servedGeneration) {
        sg_servedGeneration = generation;
        uint64_t requested = atomic_load_explicit(&sg_requestHostTime, memory_order_relaxed);
        uint64_t now = (timestamp && (timestamp->mFlags & kAudioTimeStampHostTimeValid)) ? timestamp->mHostTime : mach_absolute_time();
        double age = now > requested ? (double)(now - requested) * sg_secondsPerTick : 0;
        if (age > kRequestLifetime) {
            atomic_fetch_add_explicit(&sg_entriesDropped, 1, memory_order_relaxed);
        } else {
            uint64_t bits = atomic_load_explicit(&sg_paramsBits, memory_order_acquire);
            SGTransitionParams params = {0};
            params.sampleRate = loadDouble(&sg_rateBits);
            params.lengthFrames = (uint32_t)bits;
            params.startCutoffHz = (float)(uint32_t)(bits >> 32);
            params.startGainDb = kStartGainDb;
            SGTransitionRunStart(&sg_run, &params);
            if (SGTransitionRunActive(&sg_run)) atomic_fetch_add_explicit(&sg_entriesShaped, 1, memory_order_relaxed);
        }
    }
    if (!SGTransitionRunActive(&sg_run)) return noErr;
    if (*flags & kAudioUnitRenderAction_OutputIsSilence) {
        // Nothing to shape, but the entry is this much older; the filter's state is reset at the next sound.
        sg_run.position += frames;
        memset(sg_run.state, 0, sizeof sg_run.state);
        return noErr;
    }
    uint64_t layout = atomic_load_explicit(&sg_layout, memory_order_relaxed);
    UInt32 formatFlags = (UInt32)layout, channels = (UInt32)(layout >> 32) & 0xffff, bytes = (UInt32)(layout >> 48);
    BOOL isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0;
    BOOL split = (formatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    if (!isFloat || bytes != 4 || channels < 1) {
        sg_run.position += frames;
        atomic_fetch_add_explicit(&sg_skippedRenders, 1, memory_order_relaxed);
        return noErr;
    }
    // Buffers not laid out as the format says are left alone rather than read as noise: the format read at
    // the start can be a moment old.
    BOOL fits = split ? data->mNumberBuffers == channels : data->mNumberBuffers == 1 && data->mBuffers[0].mNumberChannels == channels;
    for (UInt32 b = 0; fits && b < data->mNumberBuffers; b++) {
        fits = data->mBuffers[b].mData && data->mBuffers[b].mDataByteSize == frames * sizeof(float) * (split ? 1 : channels);
    }
    if (!fits) {
        sg_run.position += frames;
        atomic_fetch_add_explicit(&sg_skippedRenders, 1, memory_order_relaxed);
        return noErr;
    }
    if (split) {
        float *lanes[SGTransitionChannels] = {data->mBuffers[0].mData, channels > 1 ? data->mBuffers[1].mData : NULL};
        SGTransitionRunProcess(&sg_run, lanes, channels > 1 ? 2 : 1, frames);
        // A third channel and up is left as it is; the first two are the music.
        return noErr;
    }
    // Interleaved: each channel's samples gathered into a lane, shaped and put back, a block at a time.
    static float left[SGTransitionBlock], right[SGTransitionBlock];
    float *interleaved = data->mBuffers[0].mData;
    float *lanes[SGTransitionChannels] = {left, channels > 1 ? right : NULL};
    for (UInt32 done = 0; done < frames && SGTransitionRunActive(&sg_run);) {
        UInt32 count = MIN(frames - done, (UInt32)SGTransitionBlock);
        for (UInt32 i = 0; i < count; i++) {
            left[i] = interleaved[(done + i) * channels];
            if (channels > 1) right[i] = interleaved[(done + i) * channels + 1];
        }
        SGTransitionRunProcess(&sg_run, lanes, channels > 1 ? 2 : 1, count);
        for (UInt32 i = 0; i < count; i++) {
            interleaved[(done + i) * channels] = left[i];
            if (channels > 1) interleaved[(done + i) * channels + 1] = right[i];
        }
        done += count;
    }
    return noErr;
}

#pragma mark - the parameters

static float startCutoffFor(SGTransitionsSoftness softness) {
    switch (softness) {
        case SGTransitionsSoftnessGentle: return 2500;
        case SGTransitionsSoftnessStrong: return 300;
        case SGTransitionsSoftnessMedium: break;
    }
    return 800;
}

// Any off-render thread: the next slot is filled from the keys and the output's rate, then published.
static void publishParams(void) {
    double rate = loadDouble(&sg_rateBits);
    SGTransitionParams params = {0};
    params.sampleRate = rate;
    params.lengthFrames = rate > 0 ? (uint32_t)llround(rate * SGTransitionsLengthMs() / 1000.0) : 0;
    params.startCutoffHz = startCutoffFor(SGTransitionsSoftnessChoice());
    params.startGainDb = kStartGainDb;
    uint64_t bits = (uint64_t)params.lengthFrames | ((uint64_t)(uint32_t)llround(params.startCutoffHz) << 32);
    atomic_store_explicit(&sg_paramsBits, bits, memory_order_release);
}

BOOL SGTransitionsEnabled(void) {
    return SGFlag(SGKeyTransitions, NO);
}

NSInteger SGTransitionsLengthMs(void) {
    return MAX(SGTransitionsLengthMin, MIN(SGTransitionsLengthMax, SGInt(SGKeyTransitionsLength, SGTransitionsLengthDefault)));
}

SGTransitionsSoftness SGTransitionsSoftnessChoice(void) {
    NSInteger choice = SGInt(SGKeyTransitionsSoftness, SGTransitionsSoftnessMedium);
    return choice >= SGTransitionsSoftnessGentle && choice <= SGTransitionsSoftnessStrong ? (SGTransitionsSoftness)choice : SGTransitionsSoftnessMedium;
}

void SGTransitionsSettingsChanged(void) {
    atomic_store(&sg_enabled, SGTransitionsEnabled());
    publishParams();
}

NSString *SGTransitionsStatus(void) {
    if (!SGAudioPipelineAvailable()) return @"Spotify's output is not reachable in this build";
    switch ((SGOutputState)atomic_load(&sg_outputState)) {
        case SGOutputUnseen: return @"Waiting for Spotify's output to start";
        case SGOutputUnsupported: return @"Spotify's output is not float audio; entries pass as they are";
        case SGOutputFloat: break;
    }
    unsigned shaped = atomic_load(&sg_entriesShaped), dropped = atomic_load(&sg_entriesDropped), skipped = atomic_load(&sg_skippedRenders);
    NSMutableString *text = [NSMutableString stringWithFormat:@"%u %@ softened at %g kHz", shaped, shaped == 1 ? @"entry" : @"entries", loadDouble(&sg_rateBits) / 1000];
    if (dropped) [text appendFormat:@", %u missed (output idle)", dropped];
    if (skipped) [text appendFormat:@", %u renders skipped", skipped];
    return text;
}

#pragma mark - the output unit

// The format the notify's buffers are in: the RemoteIO unit's output side (element 0, output scope), the
// hardware's, not the one Spotify hands the unit. Called by the pipeline at output start or format change,
// off the render thread.
static void prepareOutput(AudioUnit unit) {
    AudioStreamBasicDescription format = {0};
    UInt32 size = sizeof format;
    OSStatus status = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format, &size);
    UInt32 bytes = format.mBitsPerChannel / 8;
    BOOL takes = status == noErr && format.mFormatID == kAudioFormatLinearPCM && format.mSampleRate > 0 && format.mChannelsPerFrame >= 1
                 && bytes == 4 && (format.mFormatFlags & kAudioFormatFlagIsFloat);
    if (!takes) {
        atomic_store(&sg_layout, 0);
        storeDouble(&sg_rateBits, 0);
        atomic_store(&sg_outputState, SGOutputUnsupported);
        publishParams();
        return;
    }
    storeDouble(&sg_rateBits, format.mSampleRate);
    atomic_store(&sg_layout, (uint64_t)format.mFormatFlags | (uint64_t)(format.mChannelsPerFrame & 0xffff) << 32 | (uint64_t)bytes << 48);
    atomic_store(&sg_outputState, SGOutputFloat);
    publishParams();
}

#pragma mark - the player

@interface SGTransitionsObserver : NSObject <SGPlayerStateObserver>
@property (nonatomic, copy) NSString *trackURI;
@end

@implementation SGTransitionsObserver
// Main thread. A new URI while playing arms the next render; a pause and resume keeps its URI and is
// left alone, and so is the first track seen (nothing was playing before it).
- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *uri = SGURIString(state.track.URI);
    NSString *was = self.trackURI;
    if (uri.length) self.trackURI = uri;
    if (!uri.length || !was.length || [uri isEqualToString:was]) return;
    if (state.isPaused || !state.isPlaying) return;
    if (!atomic_load(&sg_enabled)) return;
    atomic_store_explicit(&sg_requestHostTime, mach_absolute_time(), memory_order_relaxed);
    atomic_fetch_add_explicit(&sg_requestGeneration, 1, memory_order_release);
}
@end

static SGTransitionsObserver *sg_observer;

%ctor {
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    sg_secondsPerTick = timebase.denom ? (double)timebase.numer / timebase.denom / 1e9 : 1e-9;
    static const SGAudioProcessor processor = {prepareOutput, rendered};
    if (!SGAudioPipelineRegister(SGAudioStageTransitions, &processor)) return;
    SGTransitionsSettingsChanged();
    dispatch_async(dispatch_get_main_queue(), ^{
        sg_observer = [SGTransitionsObserver new];
        SGAddPlayerStateObserver(sg_observer);
    });
    SGLog(@"transitions: listening for Spotify's output unit (%@)", SGTransitionsEnabled() ? @"on" : @"off");
}
