# SPDX-License-Identifier: Apache-2.0

# Copyright 2021 PANTHEON.tech
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

ARG VPP_VERSION=21.01
ARG VPP_IMAGE=ligato/vpp-base:$VPP_VERSION

FROM ${VPP_IMAGE}

RUN mkdir -p /opt/dev && apt-get update && \
    apt-get install -y git ca-certificates && \
    apt-get install -y build-essential sudo cmake ninja-build

WORKDIR /opt/dev

RUN git clone https://gerrit.fd.io/r/vpp
RUN cd vpp && \
    COMMIT=$(cat /vpp/version | sed -n 's/.*[~-]g\([a-z0-9]*\).*/\1/p' | \
        (grep . || sh -c 'echo "Cant detect commit of VPP from VPP image" 1>&2;exit 1')) && \
    git checkout $COMMIT && git show  -s

#----------------------
# build & install external plugins (ABX, ISISX)
ARG VPP_VERSION=21.01
COPY vpp/abx /tmp/abx
COPY vpp/isisx /tmp/isisx

RUN VPPVER=$(echo $VPP_VERSION | tr -d ".") && \
    cp -r /tmp/abx/vpp${VPPVER} /opt/dev/abx && \
    cp -r /tmp/isisx/vpp${VPPVER} /opt/dev/isisx    

RUN cd abx && ./build.sh /opt/dev/vpp/

RUN cp /opt/dev/abx/build/lib/vpp_plugins/abx_plugin.so \
       /usr/lib/x86_64-linux-gnu/vpp_plugins/
RUN cp /opt/dev/abx/build/abx/abx.api.json \
       /usr/share/vpp/api/core/

RUN cd ./isisx && ./build.sh /opt/dev/vpp/

RUN cp /opt/dev/isisx/build/lib/vpp_plugins/isisx_plugin.so \
       /usr/lib/x86_64-linux-gnu/vpp_plugins/
RUN cp /opt/dev/isisx/build/isisx/isisx.api.json \
       /usr/share/vpp/api/core/

# there is a bug in VPP 21.06 that api files are not built on standard location
# for external plugins, to reproduce it is enough to try to build sample-plugin
RUN if [ "$VPP_VERSION" = "21.06" ]; \
    then \
      cp /vpp-api/vapi/* /usr/include/vapi/; \
    else \
      cp /opt/dev/abx/build/vpp-api/vapi/* /usr/include/vapi/; \
    fi

CMD ["/usr/bin/vpp", "-c", "/etc/vpp/startup.conf"]
