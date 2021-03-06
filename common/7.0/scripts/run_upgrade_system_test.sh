#!/bin/bash

set -ex

TEST_ISO_JOB_URL="${TEST_ISO_JOB_URL:-https://product-ci.infra.mirantis.net/job/7.0.test_all/}"

###################### Get MIRROR HOST ###############

LOCATION_FACT=$(facter --external-dir /etc/facter/facts.d/ location)
LOCATION=${LOCATION_FACT:-bud}
CENTOS_UPDATE_HOST="http://pkg-updates.fuel-infra.org/centos6/"

case "${LOCATION}" in
    srt)
        MIRROR_HOST="http://osci-mirror-srt.srt.mirantis.net/"
        ;;
    msk)
        MIRROR_HOST="http://osci-mirror-msk.msk.mirantis.net/"
        ;;
    kha)
        MIRROR_HOST="http://osci-mirror-kha.kha.mirantis.net/"
        ;;
    poz)
        MIRROR_HOST="http://osci-mirror-poz.poz.mirantis.net/"
        ;;
    bud)
        MIRROR_HOST="http://mirror.seed-cz1.fuel-infra.org/"
        ;;
    bud-ext)
        MIRROR_HOST="http://mirror.seed-cz1.fuel-infra.org/"
        ;;
    mnv|scc)
        MIRROR_HOST="http://mirror.seed-us1.fuel-infra.org/"
        ;;
    *)
        MIRROR_HOST="http://mirror.fuel-infra.org/"
esac

# Set proper Openstack Release
if [[ ${OPENSTACK_RELEASE} == 'centos' ]]; then
	export OPENSTACK_RELEASE="CentOS"
elif [[ ${OPENSTACK_RELEASE} == 'ubuntu' ]]; then
	export OPENSTACK_RELEASE="Ubuntu"
fi

###################### Get MIRROR_UBUNTU ###############

if [[ ! "${MIRROR_UBUNTU}" ]]; then

    case "${UBUNTU_MIRROR_ID}" in
        latest-stable)
            UBUNTU_MIRROR_ID="$(curl -fsS "${TEST_ISO_JOB_URL}lastSuccessfulBuild/artifact/ubuntu_mirror_id.txt" | awk -F '[ =]' '{print $NF}')"
            UBUNTU_MIRROR_URL="${MIRROR_HOST}pkgs/${UBUNTU_MIRROR_ID}/"
            ;;
        latest)
            UBUNTU_MIRROR_URL="$(curl ${MIRROR_HOST}pkgs/ubuntu-latest.htm)"
            ;;
        *)
            UBUNTU_MIRROR_URL="${MIRROR_HOST}pkgs/${UBUNTU_MIRROR_ID}/"
    esac

    export MIRROR_UBUNTU="deb ${UBUNTU_MIRROR_URL} trusty main universe multiverse|deb ${UBUNTU_MIRROR_URL} trusty-updates main universe multiverse|deb ${UBUNTU_MIRROR_URL} trusty-security main universe multiverse"
fi

###################### Set extra 6.1 DEB and RPM repos ####

RPM_UPDATES="${MIRROR_HOST}mos/snapshots/centos-6-latest/mos6.1/updates"
RPM_SECURITY="${MIRROR_HOST}mos/snapshots/centos-6-latest/mos6.1/security"
export EXTRA_RPM_REPOS="mos-updates,${RPM_UPDATES}|mos-security,${RPM_SECURITY}"
export UPDATE_FUEL_MIRROR="${RPM_UPDATES} ${RPM_SECURITY}"
export UPDATE_MASTER=true

DEB_UPDATES="mos-updates,deb ${MIRROR_HOST}mos/snapshots/ubuntu-latest mos6.1-updates main restricted"
DEB_SECURITY="mos-security,deb ${MIRROR_HOST}mos/snapshots/ubuntu-latest mos6.1-security main restricted"
export EXTRA_DEB_REPOS="${DEB_UPDATES}|${DEB_SECURITY}"

export TIMESTAMP=$(date +%y%m%d%H%M)
export ENV_NAME="${ENV_PREFIX}.${BUILD_NUMBER}.${TIMESTAMP}"
export ENV_NAME="${ENV_NAME:0:68}"
export FUEL_STATS_ENABLED="false"

echo "export ENV_NAME=\"${ENV_NAME}\"" > "${WORKSPACE}/${DOS_ENV_NAME_PROPS_FILE:=.dos_environment_name}"

rm -rf logs/*

ISO_PATH=$(seedclient-wrapper -d -m "${BASE_ISO_MAGNET_LINK}" -v --force-set-symlink -o "${WORKSPACE}")

export MAKE_SNAPSHOT="true"

sh -x "BASE/utils/jenkins/system_tests.sh" -t test -w "${WORKSPACE}/BASE" -e "${ENV_NAME}" -o --group="${TEST_GROUP}" -i "${ISO_PATH}"

echo "Description string: ${TEST_GROUP} on ${VERSION_STRING}"

export MAKE_SNAPSHOT="false"

export TARBALL_PATH=$(seedclient-wrapper -d -m "${UPGRADE_TARBALL_MAGNET_LINK}" -v --force-set-symlink -o "${WORKSPACE}")

VERSION_STRING=$(basename "${TARBALL_PATH}" | cut -d '-' -f 2-4)
echo "Description string: ${VERSION_STRING}"

export UPGRADE_FUEL_FROM=$(basename "${ISO_PATH}" | cut -d '-' -f 2 | sed s/.iso//g)
export UPGRADE_FUEL_TO=$(basename "${TARBALL_PATH}" | cut -d '-' -f 2)

export VENV_PATH="/home/jenkins/qa-venv-7.0"

###################### Set extra 7.0 DEB and RPM repos ####
unset EXTRA_RPM_REPOS
unset UPDATE_FUEL_MIRROR
unset EXTRA_DEB_REPOS

if [[ -n "${RPM_LATEST}" ]]; then
    RPM_MIRROR="${MIRROR_HOST}mos-repos/centos/mos7.0-centos6-fuel/snapshots/"
    if [[ "${ENABLE_PROPOSED}" == "true" ]]; then
        RPM_PROPOSED="mos-proposed,${RPM_MIRROR}proposed-${RPM_LATEST}/x86_64"
        EXTRA_RPM_REPOS+="${RPM_PROPOSED}"
        UPDATE_FUEL_MIRROR="${RPM_MIRROR}proposed-${RPM_LATEST}/x86_64"
    fi
    if [[ "${ENABLE_UPDATES}" == "true" ]]; then
        RPM_UPDATES="mos-updates,${RPM_MIRROR}updates-${RPM_LATEST}/x86_64"
        if [[ -n "${EXTRA_RPM_REPOS}" ]]; then
            EXTRA_RPM_REPOS+="|"
            UPDATE_FUEL_MIRROR+=" "
        fi
        EXTRA_RPM_REPOS+="${RPM_UPDATES}"
        UPDATE_FUEL_MIRROR+="${RPM_MIRROR}updates-${RPM_LATEST}/x86_64"
    fi
    if [[ "${ENABLE_SECURITY}" == "true" ]]; then
        RPM_SECURITY="mos-security,${RPM_MIRROR}security-${RPM_LATEST}/x86_64"
        if [[ -n "${EXTRA_RPM_REPOS}" ]]; then
            EXTRA_RPM_REPOS+="|"
            UPDATE_FUEL_MIRROR+=" "
        fi
        EXTRA_RPM_REPOS+="${RPM_SECURITY}"
        UPDATE_FUEL_MIRROR+="${RPM_MIRROR}security-${RPM_LATEST}/x86_64"
    fi
    if [[ "${ENABLE_UPDATE_CENTOS}" == "true" ]]; then
        RPM_UPDATE_CENTOS="centos-security,${CENTOS_UPDATE_HOST}"
        if [[ -n "${EXTRA_RPM_REPOS}" ]]; then
            EXTRA_RPM_REPOS+="|"
            UPDATE_FUEL_MIRROR+=" "
        fi
        EXTRA_RPM_REPOS+="${RPM_UPDATE_CENTOS}"
        UPDATE_FUEL_MIRROR+="${CENTOS_UPDATE_HOST}"
    fi
    export EXTRA_RPM_REPOS
    export UPDATE_FUEL_MIRROR
fi

if [[ -n "${DEB_LATEST}" ]]; then
    DEB_MIRROR="${MIRROR_HOST}mos-repos/ubuntu/snapshots/7.0-${DEB_LATEST}"
    if [[ "${ENABLE_PROPOSED}" == "true" ]]; then
        DEB_PROPOSED="mos-proposed,deb ${DEB_MIRROR} mos7.0-proposed main restricted"
        EXTRA_DEB_REPOS+="${DEB_PROPOSED}"
    fi
    if [[ "${ENABLE_UPDATES}" == "true" ]]; then
        DEB_UPDATES="mos-updates,deb ${DEB_MIRROR} mos7.0-updates main restricted"
        if [[ -n "${EXTRA_DEB_REPOS}" ]]; then
            EXTRA_DEB_REPOS+="|"
        fi
        EXTRA_DEB_REPOS+="${DEB_UPDATES}"
    fi
    if [[ "${ENABLE_SECURITY}" == "true" ]]; then
        DEB_SECURITY="mos-security,deb ${DEB_MIRROR} mos7.0-security main restricted"
        if [[ -n "${EXTRA_DEB_REPOS}" ]]; then
            EXTRA_DEB_REPOS+="|"
        fi
        EXTRA_DEB_REPOS+="${DEB_SECURITY}"
    fi
    export EXTRA_DEB_REPOS
fi


# Use -k to reuse environment
sh -x "UPGRADE/utils/jenkins/system_tests.sh" -k -t test -w "${WORKSPACE}/UPGRADE" -e "${ENV_NAME}" -o --group="${UPGRADE_TEST_GROUP}" -i "${ISO_PATH}"
