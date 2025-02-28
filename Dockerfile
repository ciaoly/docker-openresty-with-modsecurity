
# --------------------------------------------------------------------------
FROM openresty/openresty:alpine AS build
WORKDIR /opt
# 别忘了加斜线
ARG GITHUB_MIRROR="https://ghfast.top/"

# 更新为国内镜像
RUN sed -i 's#https\?://dl-cdn.alpinelinux.org/alpine#https://mirrors.tuna.tsinghua.edu.cn/alpine#g' /etc/apk/repositories && \
    apk update && apk add --no-cache git build-base \ 
                          pcre pcre-dev openssl openssl-dev zlib zlib-dev automake \
                          libtool autoconf linux-headers libxslt-dev gd-dev geoip-dev

# libmodsecurity
RUN git clone --depth 1 -b v3/master --single-branch "${GITHUB_MIRROR}https://github.com/SpiderLabs/ModSecurity" /opt/ModSecurity/
RUN cd /opt/ModSecurity && git submodule init
RUN cd /opt/ModSecurity && GITHUB_MIRROR=${GITHUB_MIRROR} && git submodule foreach '\
    current_url=$(git config --get remote.origin.url) && \
    new_url="${GITHUB_MIRROR}${current_url#https://}" && \
    git remote set-url origin "$new_url" && \
    echo "Updated submodule URL: $new_url" \
    '
RUN cd /opt/ModSecurity && git submodule update
RUN cd /opt/ModSecurity && ./build.sh && ./configure 
RUN cd /opt/ModSecurity && make -j8 && make install

# -----------------------------------------------------------------------------

# ngx-modsecurity
RUN cd /opt && git clone --depth 1 "${GITHUB_MIRROR}https://github.com/SpiderLabs/ModSecurity-nginx.git" /opt/ModSecurity-nginx/ &&\
    nginx_version=$(openresty -v 2>&1 | awk -F '/' '{print $2}') && wget "https://openresty.org/download/openresty-${nginx_version}.tar.gz" && \
    tar -xvzf openresty-${nginx_version}.tar.gz && cd openresty-${nginx_version}/bundle/
RUN nginx_version=$(openresty -v 2>&1 | awk -F '/' '{print $2}') && \
    export LUAJIT_LIB="/usr/local/openresty/luajit/lib/" && \
    export LUAJIT_INC="$(find /usr/local/openresty/luajit/include/ -type d -name luajit-2* | head -n 1)" && \
    #export LUAJIT_INC="$PWD/$(find . -maxdepth 1 -type d -name 'LuaJIT-*' | head -n 1)/src" && \
    echo $LUAJIT_INC && \
    cd "$(find openresty-${nginx_version}/bundle/ -maxdepth 1 -type d -name 'nginx-*' | head -n 1)" && \
    COMPILEOPTIONS=$(openresty -V 2>&1 | grep -i "arguments"|cut -d ":" -f2-) && \
    eval ./configure $COMPILEOPTIONS --add-dynamic-module=/opt/ModSecurity-nginx/ && \
    make modules && mv objs/ngx_http_modsecurity_module.so /opt/

# ----------------------------------------------------------------

# 从官方基础版本构建
FROM openresty/openresty:alpine AS release

COPY --from=build /opt/ngx_http_modsecurity_module.so /usr/local/openresty/nginx/modules/
COPY --from=build /usr/local/modsecurity /usr/local/modsecurity

#RUN echo "/usr/local/modsecurity/lib" > /etc/ld.so.conf.d/modsecurity.conf && ldconfig
RUN ldconfig -n /usr/local/modsecurity/lib

#RUN usermod -u 33 www-data && usermod -G staff www-data
RUN getent group www-data ||  addgroup -g 33 www-data && \
        getent passwd www-data || adduser -D -H -u 33 -S -G www-data www-data

# 更新为国内镜像
RUN sed -i 's#https\?://dl-cdn.alpinelinux.org/alpine#https://mirrors.tuna.tsinghua.edu.cn/alpine#g' /etc/apk/repositories && \
        apk update && apk add --no-cache curl perl ca-certificates

RUN opm install ledgetech/lua-resty-http

# 镜像信息
LABEL Author="cha01"
