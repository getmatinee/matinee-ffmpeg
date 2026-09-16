// Copyright (C) 2023-2026 Swissmakers GmbH
// Author: Michael André Reber
// License: AGPL-3.0-or-later
// https://github.com/getmatinee/matinee

// Regression cases for the mapped-frame and ASS header patches. None of them
// needs a GPU, so the CPU validation build covers both
#include <stdio.h>
#include <string.h>

#include "libavformat/avformat.h"
#include "libavutil/error.h"
#include "libavutil/hwcontext.h"
#include "libavutil/mem.h"
#include "libswscale/swscale.h"

static int mapped_software_frames(int mask)
{
    AVFrame *src = av_frame_alloc(), *dst = av_frame_alloc();
    SwsContext *sws = sws_alloc_context();
    int ret = AVERROR(ENOMEM);
    if (!src || !dst || !sws)
        goto end;
    src->format = AV_PIX_FMT_YUV420P;
    src->width = src->height = 32;
    dst->format = AV_PIX_FMT_RGB24;
    dst->width = dst->height = 16;
    if (av_frame_get_buffer(src, 0) < 0 || av_frame_get_buffer(dst, 0) < 0)
        goto end;
    for (int plane = 0; plane < 3; plane++)
        memset(src->data[plane], plane ? 128 : 80,
               src->linesize[plane] * (plane ? 16 : 32));

    // The pixel format, not the presence of a retained context reference, decides
    // whether swscale converts in hardware
    AVFrame *frames[] = { src, dst };
    for (int i = 0; i < 2; i++) {
        if (!(mask & (1 << i)))
            continue;
        frames[i]->hw_frames_ctx = av_buffer_allocz(sizeof(AVHWFramesContext));
        if (!frames[i]->hw_frames_ctx)
            goto end;
        AVHWFramesContext *hwfc = (void *)frames[i]->hw_frames_ctx->data;
        hwfc->format = AV_PIX_FMT_VAAPI;
        hwfc->sw_format = AV_PIX_FMT_NV12;
    }
    ret = sws_scale_frame(sws, dst, src);
    if (ret >= 0 && !dst->data[0][0])
        ret = AVERROR_INVALIDDATA;
end:
    sws_free_context(&sws);
    av_frame_free(&src);
    av_frame_free(&dst);
    return ret;
}

static int ass_header(const char *header, size_t header_size)
{
    AVFormatContext *ctx = NULL;
    unsigned char *buffer = NULL;
    int size, ret = avformat_alloc_output_context2(&ctx, NULL, "ass", NULL);
    if (ret < 0)
        return ret;
    AVStream *stream = avformat_new_stream(ctx, NULL);
    if (!stream) {
        ret = AVERROR(ENOMEM);
        goto end;
    }
    stream->codecpar->codec_type = AVMEDIA_TYPE_SUBTITLE;
    stream->codecpar->codec_id = AV_CODEC_ID_ASS;
    stream->codecpar->extradata_size = header_size;
    stream->codecpar->extradata = av_mallocz(header_size + AV_INPUT_BUFFER_PADDING_SIZE);
    if (!stream->codecpar->extradata) {
        ret = AVERROR(ENOMEM);
        goto end;
    }
    memcpy(stream->codecpar->extradata, header, header_size);
    ret = avio_open_dyn_buf(&ctx->pb);
    if (ret < 0)
        goto end;
    ret = avformat_write_header(ctx, NULL);
    if (ret >= 0)
        ret = av_write_trailer(ctx);
    size = avio_close_dyn_buf(ctx->pb, &buffer);
    ctx->pb = NULL;
    if (ret >= 0 && (size <= 0 || memchr(buffer, 0, size)))
        ret = AVERROR_INVALIDDATA;
end:
    av_free(buffer);
    avformat_free_context(ctx);
    return ret;
}

int main(void)
{
    for (int mask = 0; mask < 4; mask++) {
        int ret = mapped_software_frames(mask);
        if (ret < 0) {
            fprintf(stderr, "mapped software frames (mask %d): %s\n", mask, av_err2str(ret));
            return 1;
        }
    }
    const char short_header[] = "[Script Info]\nScriptType: v4.00+\n[V4+ Styles]\n\0\0\0";
    const char full_header[] = "[Script Info]\nScriptType: v4.00+\n"
        "[V4+ Styles]\n[Events]\n"
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
        "\0\0\0";
    const char *headers[] = { short_header, full_header };
    const size_t sizes[] = { sizeof(short_header), sizeof(full_header) };
    for (int i = 0; i < 2; i++) {
        int ret = ass_header(headers[i], sizes[i]);
        if (ret < 0) {
            fprintf(stderr, "ASS header/trailer case %d: %s\n", i, av_err2str(ret));
            return 1;
        }
    }
    puts("PASS mapped software frames (neither/source/destination/both contexts) and ASS header");
    return 0;
}
