// Copyright (C) 2023-2026 Swissmakers GmbH
// Author: Michael André Reber
// License: AGPL-3.0-or-later
// https://github.com/getmatinee/matinee

// ASS header and trailer bounds, exercised without a GPU
#include <stdio.h>
#include <string.h>

#include "libavformat/avformat.h"
#include "libavutil/error.h"
#include "libavutil/mem.h"

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
    puts("PASS ASS header and trailer bounds");
    return 0;
}
