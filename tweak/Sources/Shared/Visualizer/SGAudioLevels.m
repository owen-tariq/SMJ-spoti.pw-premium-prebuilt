// SPDX-License-Identifier: MIT
// The visualizer stage of the audio pipeline: the output buffer mixed down to mono in fixed chunks, fed
// through SGAudioLevelsMath.h, and the result published to the main thread through a seqlock. The
// buffer's format is read off the render thread in prepare, the way Music Haptics reads it
// (Shared/Haptics/MusicHaptics.x), and packed into one word so the render thread never sees half a change.
#import <AudioToolbox/AudioToolbox.h>
#import <mach/mach_time.h>
#import <stdatomic.h>
#import "Core/SGLog.h"
#import "Shared/Audio/SGAudioPipeline.h"
#import "SGAudioLevels.h"
#import "SGAudioLevelsMath.h"

enum { kMonoFrames = 2048 };

static atomic_bool sg_enabled, sg_registered;
static atomic_uint_fast64_t sg_sampleRateBits, sg_layout;   // layout: format flags, then channels, then bytes per sample

// The seqlock: odd while the render thread writes, even once a result is whole. The reader copies between
// two equal even reads. Only the render thread writes; the sequence inside the struct counts buffers.
static atomic_uint sg_seq;
static SGAudioLevels sg_slot;
static atomic_uint_fast64_t sg_count;
// Sequences at or under this were published before the last enable: a reader must not take them.
static atomic_uint_fast64_t sg_floor;

// Render thread only.
static SGAudioLevelsAnalyzer sg_analyzer;
static float sg_mono[kMonoFrames];
static double sg_analyzedRate;

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

static inline float sampleAt(const void *data, UInt32 index, UInt32 bytes, bool isFloat, UInt32 fraction) {
    if (bytes == 4) {
        if (isFloat) return ((const float *)data)[index];
        int32_t value = ((const int32_t *)data)[index];
        return fraction ? (float)((double)value / (double)(1ull << (fraction & 63))) : (float)(value / 2147483648.0);
    }
    return ((const int16_t *)data)[index] / 32768.0f;
}

static void publish(const SGAudioLevelsResult *result, double sampleRate, uint64_t hostTime) {
    unsigned seq = atomic_load_explicit(&sg_seq, memory_order_relaxed);
    atomic_store_explicit(&sg_seq, seq + 1, memory_order_relaxed);
    atomic_thread_fence(memory_order_release);
    sg_slot.rms = result->rms;
    sg_slot.peak = result->peak;
    sg_slot.low = result->low;
    sg_slot.mid = result->mid;
    sg_slot.high = result->high;
    sg_slot.sampleRate = sampleRate;
    sg_slot.frames = result->frames;
    sg_slot.sequence = atomic_fetch_add_explicit(&sg_count, 1, memory_order_relaxed) + 1;
    sg_slot.hostTime = hostTime;
    atomic_thread_fence(memory_order_release);
    atomic_store_explicit(&sg_seq, seq + 2, memory_order_release);
}

// The audio is never touched: this reads the buffer bound for the speaker after the other stages have had it.
static OSStatus rendered(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp, UInt32 bus,
                         UInt32 frames, AudioBufferList *data) {
    if (!atomic_load_explicit(&sg_enabled, memory_order_relaxed)) return noErr;
    if (!flags || !(*flags & kAudioUnitRenderAction_PostRender) || bus != 0 || !data || !data->mNumberBuffers || !frames) return noErr;
    double sampleRate = loadDouble(&sg_sampleRateBits);
    if (sampleRate <= 0) return noErr;
    uint64_t hostTime = timestamp && (timestamp->mFlags & kAudioTimeStampHostTimeValid) ? timestamp->mHostTime : 0;
    if (sampleRate != sg_analyzedRate) {
        SGAudioLevelsAnalyzerReset(&sg_analyzer, sampleRate);
        sg_analyzedRate = sampleRate;
    }
    SGAudioLevelsResult result;
    if (*flags & kAudioUnitRenderAction_OutputIsSilence) {
        // Silence is a result too: the glow has to fall when the song stops.
        memset(&result, 0, sizeof result);
        result.frames = frames;
        SGAudioLevelsClearState(&sg_analyzer);
        publish(&result, sampleRate, hostTime);
        return noErr;
    }

    uint64_t layout = atomic_load_explicit(&sg_layout, memory_order_relaxed);
    UInt32 formatFlags = (UInt32)layout, channels = (UInt32)(layout >> 32) & 0xffff, bytes = (UInt32)(layout >> 48);
    bool isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0;
    bool split = (formatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    UInt32 fraction = (formatFlags & kLinearPCMFormatFlagsSampleFractionMask) >> kLinearPCMFormatFlagsSampleFractionShift;
    if ((bytes != 2 && bytes != 4) || channels < 1) return noErr;
    bool fits = split ? data->mNumberBuffers == channels : data->mNumberBuffers == 1 && data->mBuffers[0].mNumberChannels == channels;
    for (UInt32 b = 0; fits && b < data->mNumberBuffers; b++) {
        fits = data->mBuffers[b].mData && data->mBuffers[b].mDataByteSize >= frames * bytes * (split ? 1 : channels);
    }
    if (!fits) return noErr;

    const void *left = data->mBuffers[0].mData, *right = split && channels > 1 ? data->mBuffers[1].mData : left;
    UInt32 stride = split ? 1 : channels, rightOffset = !split && channels > 1 ? 1 : 0;
    SGAudioLevelsAnalyzerBegin(&sg_analyzer);
    for (UInt32 done = 0; done < frames;) {
        UInt32 count = frames - done < (UInt32)kMonoFrames ? frames - done : (UInt32)kMonoFrames;
        for (UInt32 i = 0; i < count; i++) {
            UInt32 at = (done + i) * stride;
            sg_mono[i] = 0.5f * (sampleAt(left, at, bytes, isFloat, fraction) + sampleAt(right, at + rightOffset, bytes, isFloat, fraction));
        }
        SGAudioLevelsAnalyzerFeed(&sg_analyzer, sg_mono, count);
        done += count;
    }
    SGAudioLevelsAnalyzerEnd(&sg_analyzer, &result);
    publish(&result, sampleRate, hostTime);
    return noErr;
}

// Off the render thread, at start and on a format change: the output side of the RemoteIO unit, the
// hardware's format, which is what the notify's buffers are in.
static void readFormat(AudioUnit unit) {
    AudioStreamBasicDescription format = {0};
    UInt32 size = sizeof format;
    OSStatus status = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format, &size);
    UInt32 bytes = format.mBitsPerChannel / 8;
    bool takes = status == noErr && format.mFormatID == kAudioFormatLinearPCM && format.mSampleRate > 0 && format.mChannelsPerFrame >= 1
                 && (bytes == 2 || bytes == 4) && ((format.mFormatFlags & kAudioFormatFlagIsFloat) || (format.mFormatFlags & kAudioFormatFlagIsSignedInteger));
    if (!takes) {
        atomic_store(&sg_layout, 0);
        storeDouble(&sg_sampleRateBits, 0);
        static int logged;
        if (logged++ < 3) SGLog(@"audio levels: output format not readable (status %d), nothing measured", (int)status);
        return;
    }
    storeDouble(&sg_sampleRateBits, format.mSampleRate);
    atomic_store(&sg_layout, (uint64_t)format.mFormatFlags | (uint64_t)(format.mChannelsPerFrame & 0xffff) << 32 | (uint64_t)bytes << 48);
}

#pragma mark - the public API

void SGAudioLevelsEnabled(bool on) {
    bool was = atomic_exchange(&sg_enabled, on);
    if (was == on) return;
    // The seqlock has one writer, the render thread; this thread only raises the floor so anything
    // published so far reads as stale (a reader must not take the last song's levels for this one's).
    if (on) atomic_store_explicit(&sg_floor, atomic_load_explicit(&sg_count, memory_order_relaxed), memory_order_release);
    SGLog(@"audio levels: %@", on ? @"listening" : @"off");
}

bool SGAudioLevelsRead(SGAudioLevels *out) {
    if (!out) return false;
    SGAudioLevels copy;
    enum { kTries = 32 };
    for (int attempt = 0; attempt < kTries; attempt++) {
        unsigned before = atomic_load_explicit(&sg_seq, memory_order_acquire);
        if (before & 1) continue;
        atomic_thread_fence(memory_order_acquire);
        copy = sg_slot;
        atomic_thread_fence(memory_order_acquire);
        unsigned after = atomic_load_explicit(&sg_seq, memory_order_acquire);
        if (before != after) continue;
        if (copy.sequence == 0 || copy.sequence <= atomic_load_explicit(&sg_floor, memory_order_acquire)) break;
        *out = copy;
        return true;
    }
    memset(out, 0, sizeof *out);
    return false;
}

bool SGAudioLevelsAvailable(void) {
    return atomic_load(&sg_registered) && SGAudioPipelineAvailable();
}

__attribute__((constructor)) static void SGAudioLevelsInstall(void) {
    static const SGAudioProcessor processor = {readFormat, rendered};
    if (!SGAudioPipelineRegister(SGAudioStageVisualizer, &processor)) return;
    atomic_store(&sg_registered, true);
}
