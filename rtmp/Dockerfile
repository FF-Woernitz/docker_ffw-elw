FROM alpine:3.22

ARG HLS_JS_VERSION=1.5.20

RUN apk add --no-cache nginx nginx-mod-rtmp ffmpeg tzdata \
    && mkdir -p /recordings /var/hls /var/www/rtmp \
    && chown nginx:nginx /recordings /var/hls

COPY nginx.conf /etc/nginx/nginx.conf
COPY www/ /var/www/rtmp/
COPY flv2mp4.sh /usr/local/bin/flv2mp4.sh
# Strips Windows line endings, which would break the shebang
RUN sed -i 's/\r$//' /usr/local/bin/flv2mp4.sh \
    && chmod 755 /usr/local/bin/flv2mp4.sh

# hls.js is bundled so the player also works without internet access in the vehicle
ADD https://cdn.jsdelivr.net/npm/hls.js@${HLS_JS_VERSION}/dist/hls.min.js /var/www/rtmp/hls.min.js
RUN chmod 644 /var/www/rtmp/hls.min.js \
    && nginx -t

EXPOSE 80 1935

CMD ["nginx", "-g", "daemon off;"]
