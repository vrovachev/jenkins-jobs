#!/bin/bash

set -ex

TEST_ISO_JOB_URL="${JENKINS_URL}job/${ENV_PREFIX:0:3}.test_all/"

#### Set statistics job-group properties for swarm tests ####

# Temporary disabled due to https://bugs.launchpad.net/fuel/+bug/1605734
# FUEL_STATS_HOST="fuel-collect-systest.infra.mirantis.net"
# ANALYTICS_IP="fuel-stats-systest.infra.mirantis.net"
# export FUEL_STATS_HOST="${FUEL_STATS_HOST}"
# export ANALYTICS_IP="${ANALYTICS_IP}"

###################### Get MIRROR HOST ###############

LOCATION_FACT=$(facter --external-dir /etc/facter/facts.d/ location)
LOCATION=${LOCATION_FACT:-bud}
UBUNTU_MIRROR_ID=${UBUNTU_MIRROR_ID:-latest}

case "${LOCATION}" in
    srt)
        MIRROR_HOST="http://osci-mirror-srt.srt.mirantis.net/pkgs/"
        ;;
    msk)
        MIRROR_HOST="http://osci-mirror-msk.msk.mirantis.net/pkgs/"
        ;;
    kha)
        MIRROR_HOST="http://osci-mirror-kha.kha.mirantis.net/pkgs/"
        ;;
    poz)
        MIRROR_HOST="http://osci-mirror-poz.poz.mirantis.net/pkgs/"
        ;;
    bud)
        MIRROR_HOST="http://mirror.seed-cz1.fuel-infra.org/pkgs/"
        ;;
    bud-ext)
        MIRROR_HOST="http://mirror.seed-cz1.fuel-infra.org/pkgs/"
        ;;
    mnv|scc)
        MIRROR_HOST="http://mirror.seed-us1.fuel-infra.org/pkgs/"
        ;;
    *)
        MIRROR_HOST="http://mirror.fuel-infra.org/pkgs/"
esac

###################### Get MIRROR_UBUNTU ###############

if [[ ! "${MIRROR_UBUNTU}" ]]; then

    case "${UBUNTU_MIRROR_ID}" in
        latest-stable)
            UBUNTU_MIRROR_ID="$(curl -fsS "${TEST_ISO_JOB_URL}lastSuccessfulBuild/artifact/ubuntu_mirror_id.txt" | awk -F '[ =]' '{print $NF}')"
            UBUNTU_MIRROR_URL="${MIRROR_HOST}${UBUNTU_MIRROR_ID}/"
            ;;
        latest)
            UBUNTU_MIRROR_URL="$(curl ${MIRROR_HOST}ubuntu-latest.htm)"
            ;;
        *)
            UBUNTU_MIRROR_URL="${MIRROR_HOST}${UBUNTU_MIRROR_ID}/"
    esac

    export MIRROR_UBUNTU="deb ${UBUNTU_MIRROR_URL} trusty main universe multiverse|deb ${UBUNTU_MIRROR_URL} trusty-updates main universe multiverse|deb ${UBUNTU_MIRROR_URL} trusty-security main universe multiverse|deb ${UBUNTU_MIRROR_URL} trusty-proposed main universe multiverse"
fi

rm -rf logs/*

ENV_NAME=$ENV_PREFIX.$BUILD_NUMBER.$BUILD_ID
ENV_NAME=${ENV_NAME:0:68}

ISO_PATH=$(seedclient-wrapper -d -m "${MAGNET_LINK}" -v --force-set-symlink -o "${WORKSPACE}")

VERSION_STRING=$(basename "${ISO_PATH}" | cut -d '-' -f 2-3)
echo "Description string: ${TEST_GROUP} on ${VERSION_STRING}"

export MAKE_SNAPSHOT=${MAKE_SNAPSHOT:-false}

function join() {
    local __sep="${1}"
    local __head="${2}"
    local __tail="${3}"

    if [[ -n "${__head}" ]]; then
        echo "${__head}${__sep}${__tail}"
    else
        echo "${__tail}"
    fi
}

function to_uppercase() {
    echo "$1" | awk '{print toupper($0)}'
}

__space=' '
__pipe='|'


# Adding MOS rpm repos to
# - UPDATE_FUEL_MIRROR - will be used for master node
# - EXTRA_RPM_REPOS - will be used for nodes in cluster

for _dn in  "os"        \
            "proposed"  \
            "updates"   \
            "holdback"  \
            "hotfix"    \
            "security"  ; do
    # a pointer to variable name which holds value of enable flag for this dist name
    __enable_ptr="ENABLE_MOS_CENTOS_$(to_uppercase "${_dn}")"
    if [[ "${!__enable_ptr}" = true ]] ; then
        # a pointer to variable name which holds repo id
        __repo_id_ptr="MOS_CENTOS_$(to_uppercase "${_dn}")_MIRROR_ID"
        __repo_url="http://${MIRROR_HOST}/mos-repos/centos/mos9.0-centos7/snapshots/${!__repo_id_ptr}/x86_64"
        __repo_name="mos-${_dn},${__repo_url}"
        UPDATE_FUEL_MIRROR="$(join "${__space}" "${UPDATE_FUEL_MIRROR}" "${__repo_url}" )"
        EXTRA_RPM_REPOS="$(join "${__pipe}" "${EXTRA_RPM_REPOS}" "${__repo_name}" )"
    fi
done

# UPDATE_MASTER=true in case when we have set some repos
# otherwise there will be no reason to start updating without any repos to update from

if [[ -n "${UPDATE_FUEL_MIRROR}" ]] ; then
    UPDATE_MASTER=${UPDATE_MASTER:-true}
fi

# Adding MOS deb repos to
# - EXTRA_DEB_REPOS - will be used for nodes in cluster

for _dn in  "proposed"  \
            "updates"   \
            "holdback"  \
            "hotfix"    \
            "security"  ; do
    # a pointer to variable name which holds value of enable flag for this dist name
    __enable_ptr="ENABLE_MOS_UBUNTU_$(to_uppercase "${_dn}")"
    # a pointer to variable name which holds repo id
    __repo_id_ptr="MOS_UBUNTU_MIRROR_ID"
    __repo_url="http://${MIRROR_HOST}/mos-repos/ubuntu/snapshots/${!__repo_id_ptr}"
    if [[ "${!__enable_ptr}" = true ]] ; then
        __repo_name="mos-${_dn},deb ${__repo_url} mos9.0-${_dn} main restricted"
        EXTRA_DEB_REPOS="$(join "${__pipe}" "${EXTRA_DEB_REPOS}" "${__repo_name}")"
    fi
done


export UPDATE_FUEL_MIRROR   # for fuel-qa
export UPDATE_MASTER        # for fuel-qa
export EXTRA_RPM_REPOS      # for fuel-qa
export EXTRA_DEB_REPOS      # for fuel-qa

################ PLUGINS  ###############

PLUGINS=plugins_data

# clean old plugins dir
rm -rf ${PLUGINS}
mkdir -p ${PLUGINS}

export EXAMPLE_PLUGIN_PATH="${PLUGINS}/fuel_plugin_example.fp"
export EXAMPLE_PLUGIN_V3_PATH="${PLUGINS}/fuel_plugin_example_v3.noarch.rpm"
export EXAMPLE_PLUGIN_V4_PATH="${PLUGINS}/fuel_plugin_example_v4_hotpluggable.noarch.rpm"
export SEPARATE_SERVICE_DB_PLUGIN_PATH="${PLUGINS}/detach-database-1.1-1.1.0-1.noarch.rpm"
export SEPARATE_SERVICE_RABBIT_PLUGIN_PATH="${PLUGINS}/detach-rabbitmq-1.1-1.1.2-1.noarch.rpm"
export SEPARATE_SERVICE_KEYSTONE_PLUGIN_PATH="${PLUGINS}/detach-keystone-1.0-1.0.2-1.noarch.rpm"
export SEPARATE_SERVICE_HAPROXY_PLUGIN_PATH="${PLUGINS}/detach_haproxy-2.0-2.0.0-1.noarch.rpm"
export SEPARATE_SERVICE_BALANCER_PLUGIN_PATH="${PLUGINS}/external_loadbalancer-2.0-2.0.0-1.noarch.rpm"

echo "export ENV_NAME=\"${ENV_NAME}\"" > "${WORKSPACE}/${DOS_ENV_NAME_PROPS_FILE:=.dos_environment_name}"

curl -s "${EXAMPLE_PLUGIN_URL}" -o ${EXAMPLE_PLUGIN_PATH}
curl -s "${EXAMPLE_PLUGIN_V3_URL}" -o ${EXAMPLE_PLUGIN_V3_PATH}
curl -s "${EXAMPLE_PLUGIN_V4_URL}" -o ${EXAMPLE_PLUGIN_V4_PATH}
curl -s "${SEPARATE_SERVICE_DB_PLUGIN_URL}" -o ${SEPARATE_SERVICE_DB_PLUGIN_PATH}
curl -s "${SEPARATE_SERVICE_RABBIT_PLUGIN_URL}" -o ${SEPARATE_SERVICE_RABBIT_PLUGIN_PATH}
curl -s "${SEPARATE_SERVICE_KEYSTONE_PLUGIN_URL}" -o ${SEPARATE_SERVICE_KEYSTONE_PLUGIN_PATH}
curl -s "${SEPARATE_SERVICE_HAPROXY_PLUGIN_URL}" -o ${SEPARATE_SERVICE_HAPROXY_PLUGIN_PATH}
curl -s "${SEPARATE_SERVICE_BALANCER_PLUGIN_URL}" -o ${SEPARATE_SERVICE_BALANCER_PLUGIN_PATH}


sh -x "utils/jenkins/system_tests.sh" -t test -w "${WORKSPACE}" -e "${ENV_NAME}" -o --group="${TEST_GROUP}" -i "${ISO_PATH}"
