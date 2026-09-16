// Copyright (C) 2023-2026 Swissmakers GmbH
// Author: Michael André Reber
// License: AGPL-3.0-or-later
// https://github.com/getmatinee/matinee

// The real filter allocator with a hardware pool stub, so padding and failure paths run without a GPU
#include "libavutil/hwcontext.h"

static int fail_allocation;
static int padded_hw_buffer(AVBufferRef *pool, AVFrame *frame, int flags)
{
    AVHWFramesContext *context = (AVHWFramesContext *)pool->data;
    if (fail_allocation)
        return AVERROR(ENOMEM);
    frame->format = context->format;
    frame->width = context->width;
    frame->height = context->height;
    frame->hw_frames_ctx = av_buffer_ref(pool);
    return frame->hw_frames_ctx ? 0 : AVERROR(ENOMEM);
}

#define av_hwframe_get_buffer padded_hw_buffer
#include "libavfilter/video.c"
#undef av_hwframe_get_buffer

int main(void)
{
    FilterLinkInternal link = { 0 };
    AVHWFramesContext *context;
    AVFrame *frame;
    int ret = 1;
    link.l.pub.format = AV_PIX_FMT_CUDA;
    link.l.hw_frames_ctx = av_buffer_allocz(sizeof(*context));
    if (!link.l.hw_frames_ctx)
        return 1;
    context = (AVHWFramesContext *)link.l.hw_frames_ctx->data;
    context->format = AV_PIX_FMT_CUDA;
    context->width = 2048;
    context->height = 1088;
    frame = ff_default_get_video_buffer2(&link.l.pub, 1920, 1080, 32);
    if (!frame || frame->width != 1920 || frame->height != 1080) {
        fprintf(stderr, "hardware padding leaked into visible dimensions: %dx%d\n",
                frame ? frame->width : 0, frame ? frame->height : 0);
        av_frame_free(&frame);
        goto end;
    }
    av_frame_free(&frame);
    frame = ff_default_get_video_buffer2(&link.l.pub, 4096, 1080, 32);
    if (frame) {
        fputs("an undersized hardware pool was accepted\n", stderr);
        av_frame_free(&frame);
        goto end;
    }
    fail_allocation = 1;
    if (ff_default_get_video_buffer2(&link.l.pub, 1920, 1080, 32))
        goto end;
    puts("PASS hardware allocation preserves visible dimensions and rejects undersized pools");
    ret = 0;
end:
    av_buffer_unref(&link.l.hw_frames_ctx);
    return ret;
}
