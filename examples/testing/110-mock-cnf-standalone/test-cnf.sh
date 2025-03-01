#!/usr/bin/env bash

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

trap "exit 1" TERM
export TOP_PID=$$

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

function check_rv { # parameters: actual rv, expected rv, error message
    if [ $1 -ne $2 ]; then
        echo "Fail"
        echo "------------------------------------------------"
        echo -e "${RED}[FAIL] ${3}${NC}"
        echo "------------------------------------------------"
        kill -s TERM $TOP_PID
    else
        echo "OK"
    fi
}

function check_in_sync {
    echo -n "Checking if mock CNF 1 is in-sync ... "
    docker exec mockcnf1 curl -X POST localhost:9191/scheduler/downstream-resync?verbose=1 2>&1 \
        | grep -qi -E "Executed|error"
    check_rv $? 1 "Mock CNF 1 is not in-sync"
}

# This is temporary workaround to make the test pass.
# Some Linux update between 5.11.0-27-generic and 5.11.0-37-generic (from around
# september 2021) increased maximum mtu from 65536 to 65575, so linux now by
# default sets the mtu of device vrf1 to 65575. StoneWork (or vpp-agent) then
# sets it to 65536 during resync (but not during initial configuration), which
# causes the "check_in_sync" function to fail.
docker exec mockcnf1 ip link set dev vrf1 mtu 65536

check_in_sync

# test JSON schema
schema=$(docker exec mockcnf1 curl localhost:9191/info/configuration/jsonschema 2>/dev/null)

echo -n "Checking mock CNF 1 model in JSON schema ... "
echo $schema | grep -q '"mock1Config": {'
check_rv $? 0 "Mock CNF 1 model is missing in JSON schema"

echo -n "Checking route in mock CNF 1 ... "
docker exec mockcnf1 ip route show table 1 | grep -q "7.7.7.7 dev tap"
check_rv $? 0 "Mock CNF 1 has not configured route"

echo -n "Updating config ... "
docker exec mockcnf1 agentctl config update --replace /etc/mockcnf/config/running-config.yaml >/dev/null 2>&1
check_rv $? 0 "Config update failed"

../utils.sh waitForAgentConfig mockcnf1 74 10 # mock CNFs make changes asynchronously

# This is temporary workaround to make the test pass (see comment above).
docker exec mockcnf1 ip link set dev vrf2 mtu 65536

check_in_sync

echo -n "Checking re-configured route in mock CNF 1 ... "
docker exec mockcnf1 ip route show table 2 | grep -q "7.7.7.7 dev tap"
check_rv $? 0 "Mock CNF 1 has not re-configured route"

echo "------------------------------------------------"
echo -e "${GREEN}[OK] Test successful${NC}"
echo "------------------------------------------------"
