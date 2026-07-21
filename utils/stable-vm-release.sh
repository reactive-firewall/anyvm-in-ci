#! /bin/bash
#
# SPDX-License-Identifier: BSD-0-Clause OR MIT-0
#
# Disclaimer of Warranties.
# A. YOU EXPRESSLY ACKNOWLEDGE AND AGREE THAT, TO THE EXTENT PERMITTED BY
#    APPLICABLE LAW, USE OF THIS SHELL SCRIPT AND ANY SERVICES PERFORMED
#    BY OR ACCESSED THROUGH THIS SHELL SCRIPT IS AT YOUR SOLE RISK AND
#    THAT THE ENTIRE RISK AS TO SATISFACTORY QUALITY, PERFORMANCE, ACCURACY AND
#    EFFORT IS WITH YOU.
#
# B. TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, THIS SHELL SCRIPT
#    AND SERVICES ARE PROVIDED "AS IS" AND "AS AVAILABLE", WITH ALL FAULTS AND
#    WITHOUT WARRANTY OF ANY KIND, AND THE AUTHOR OF THIS SHELL SCRIPT'S LICENSORS
#    (COLLECTIVELY REFERRED TO AS "THE AUTHOR" FOR THE PURPOSES OF THIS DISCLAIMER)
#    HEREBY DISCLAIM ALL WARRANTIES AND CONDITIONS WITH RESPECT TO THIS SHELL SCRIPT
#    SOFTWARE AND SERVICES, EITHER EXPRESS, IMPLIED OR STATUTORY, INCLUDING, BUT
#    NOT LIMITED TO, THE IMPLIED WARRANTIES AND/OR CONDITIONS OF
#    MERCHANTABILITY, SATISFACTORY QUALITY, FITNESS FOR A PARTICULAR PURPOSE,
#    ACCURACY, QUIET ENJOYMENT, AND NON-INFRINGEMENT OF THIRD PARTY RIGHTS.
#
# C. THE AUTHOR DOES NOT WARRANT AGAINST INTERFERENCE WITH YOUR ENJOYMENT OF THE
#    THE AUTHOR's SOFTWARE AND SERVICES, THAT THE FUNCTIONS CONTAINED IN, OR
#    SERVICES PERFORMED OR PROVIDED BY, THIS SHELL SCRIPT WILL MEET YOUR
#    REQUIREMENTS, THAT THE OPERATION OF THIS SHELL SCRIPT OR SERVICES WILL
#    BE UNINTERRUPTED OR ERROR-FREE, THAT ANY SERVICES WILL CONTINUE TO BE MADE
#    AVAILABLE, THAT THIS SHELL SCRIPT OR SERVICES WILL BE COMPATIBLE OR
#    WORK WITH ANY THIRD PARTY SOFTWARE, APPLICATIONS OR THIRD PARTY SERVICES,
#    OR THAT DEFECTS IN THIS SHELL SCRIPT OR SERVICES WILL BE CORRECTED.
#    INSTALLATION OF THIS THE AUTHOR SOFTWARE MAY AFFECT THE USABILITY OF THIRD
#    PARTY SOFTWARE, APPLICATIONS OR THIRD PARTY SERVICES.
#
# D. YOU FURTHER ACKNOWLEDGE THAT THIS SHELL SCRIPT AND SERVICES ARE NOT
#    INTENDED OR SUITABLE FOR USE IN SITUATIONS OR ENVIRONMENTS WHERE THE FAILURE
#    OR TIME DELAYS OF, OR ERRORS OR INACCURACIES IN, THE CONTENT, DATA OR
#    INFORMATION PROVIDED BY THIS SHELL SCRIPT OR SERVICES COULD LEAD TO
#    DEATH, PERSONAL INJURY, OR SEVERE PHYSICAL OR ENVIRONMENTAL DAMAGE,
#    INCLUDING WITHOUT LIMITATION THE OPERATION OF NUCLEAR FACILITIES, AIRCRAFT
#    NAVIGATION OR COMMUNICATION SYSTEMS, AIR TRAFFIC CONTROL, LIFE SUPPORT OR
#    WEAPONS SYSTEMS.
#
# E. NO ORAL OR WRITTEN INFORMATION OR ADVICE GIVEN BY THE AUTHOR
#    SHALL CREATE A WARRANTY. SHOULD THIS SHELL SCRIPT OR SERVICES PROVE DEFECTIVE,
#    YOU ASSUME THE ENTIRE COST OF ALL NECESSARY SERVICING, REPAIR OR CORRECTION.
#
#    Limitation of Liability.
# F. TO THE EXTENT NOT PROHIBITED BY APPLICABLE LAW, IN NO EVENT SHALL THE AUTHOR
#    BE LIABLE FOR PERSONAL INJURY, OR ANY INCIDENTAL, SPECIAL, INDIRECT OR
#    CONSEQUENTIAL DAMAGES WHATSOEVER, INCLUDING, WITHOUT LIMITATION, DAMAGES
#    FOR LOSS OF PROFITS, CORRUPTION OR LOSS OF DATA, FAILURE TO TRANSMIT OR
#    RECEIVE ANY DATA OR INFORMATION, BUSINESS INTERRUPTION OR ANY OTHER
#    COMMERCIAL DAMAGES OR LOSSES, ARISING OUT OF OR RELATED TO YOUR USE OR
#    INABILITY TO USE THIS SHELL SCRIPT OR SERVICES OR ANY THIRD PARTY
#    SOFTWARE OR APPLICATIONS IN CONJUNCTION WITH THIS SHELL SCRIPT OR
#    SERVICES, HOWEVER CAUSED, REGARDLESS OF THE THEORY OF LIABILITY (CONTRACT,
#    TORT OR OTHERWISE) AND EVEN IF THE AUTHOR HAS BEEN ADVISED OF THE
#    POSSIBILITY OF SUCH DAMAGES. SOME JURISDICTIONS DO NOT ALLOW THE EXCLUSION
#    OR LIMITATION OF LIABILITY FOR PERSONAL INJURY, OR OF INCIDENTAL OR
#    CONSEQUENTIAL DAMAGES, SO THIS LIMITATION MAY NOT APPLY TO YOU. In no event
#    shall THE AUTHOR's total liability to you for all damages (other than as may
#    be required by applicable law in cases involving personal injury) exceed
#    the amount of five dollars ($5.00). The foregoing limitations will apply
#    even if the above stated remedy fails of its essential purpose.
################################################################################

test -x "$(command -v curl)" || test -x "$(command -v wget)" || exit 126 ;
test -x "$(command -v grep)" || exit 126 ;
test -x "$(command -v sed)" || exit 126 ;
test -x "$(command -v tr)" || exit 126 ;

# freebsd / ghostbsd / openbsd / netbsd / dragonflybsd / midnightbsd / solaris / omnios / openindiana / tribblix / haiku / hurd / ubuntu / blissos / front9

# get_stable_vm_release NAME
# Portable /bin/sh-compatible function returning a single token: the default
# "builder' release for NAME (one of the supported values).
# Exits non‑zero and prints nothing on unknown NAME or failure.
# Uses curl and standard POSIX tools only.
get_stable_vm_release() {
  name=$(printf '%s' "${1:-}" | awk '{print tolower($0)}')
  [ -n "$name" ] || return 1

  fetch() {
    url=$1

    case $url in
      https://api.github.com/*)
        auth_header=
        if [ -n "${ANYVM_TOKEN:-${GH_TOKEN:-}}" ]; then
          auth_header="Authorization: Bearer ${ANYVM_TOKEN:-${GH_TOKEN:-}}"
        fi
        ;;
      *)
        auth_header=
        ;;
    esac

    if command -v curl >/dev/null 2>&1; then
      if [ -n "$auth_header" ]; then
        curl -fsL -H "Accept: application/vnd.github+json" -H "$auth_header" --max-time 15 "$url" || return 1
      else
        curl -fsL -H "Accept: application/vnd.github+json" --max-time 15 "$url" || return 1
      fi
    elif command -v wget >/dev/null 2>&1; then
      if [ -n "$auth_header" ]; then
        wget -qO- --header="Accept: application/vnd.github+json" --header="$auth_header" --timeout=15 "$url" || return 1
      else
        wget -qO- --header="Accept: application/vnd.github+json" --timeout=15 "$url" || return 1
      fi
    else
      return 1
    fi
  }

  gh_builder_releases() {
    local repo_stub="$1"
    local response urls

    response="$(fetch "https://api.github.com/repos/${repo_stub}/releases/latest")" || return 1

    if command -v jq >/dev/null 2>&1; then
      urls="$(printf '%s\n' "$response" | jq -r '.assets[]?.browser_download_url // empty')"
    else
      urls="$(printf '%s\n' "$response" \
        | grep -oE '"browser_download_url":[[:space:]]*"[^"]+"' \
        | sed -E 's/.*"browser_download_url":[[:space:]]*"([^"]+)".*/\1/')"
    fi

    [[ -n "$urls" ]] || return 1
    printf '%s\n' "$urls"
  }

  gh_latest_release() {
    local repo_stub="$1"
    gh_builder_releases "${repo_stub}" | grep -iEe "(.qemu|.qcow2.zst)$" | grep -oiEe "[/]{1}[^/]+$" | cut -d- -f2-2 | sed -E 's#.*/[^-]+-([0-9]+(\.[0-9]+){1,2})(-.+)?\.(qemu|qcow2\.zst)$#\1#' | sed -E 's/\.(qemu|qcow2\.zst)$//' | (sort -V 2>/dev/null || sort) | tail -n1;
  }

  case "$name" in
    freebsd)
      gh_latest_release "anyvm-org/freebsd-builder" || return 1
      ;;
    ghostbsd)
      gh_latest_release "anyvm-org/ghostbsd-builder" || return 1
      ;;
    openbsd)
      gh_latest_release "anyvm-org/openbsd-builder" || return 1
      ;;
    netbsd)
     gh_latest_release "anyvm-org/netbsd-builder" || return 1
      ;;
    dragonflybsd|dragonfly)
      gh_latest_release "anyvm-org/dragonflybsd-builder" || return 1
      ;;
    midnightbsd|midnight)
      gh_latest_release "anyvm-org/midnightbsd-builder" || return 1
      ;;
    solaris)
      gh_latest_release "anyvm-org/solaris-builder" || return 1
      ;;
    omnios)
      gh_latest_release "anyvm-org/omnios-builder" || return 1
      ;;
    openindiana)
      gh_latest_release "anyvm-org/openindiana-builder" || return 1
      ;;
    tribblix)
      gh_latest_release "anyvm-org/tribblix-builder" || return 1
      ;;
    haiku)
      gh_latest_release "anyvm-org/haiku-builder" || return 1
      ;;
    hurd)
      gh_latest_release "anyvm-org/hurd-builder" || return 1
      ;;
    ubuntu)
      gh_latest_release "anyvm-org/ubuntu-builder" || return 1
      ;;
    blissos|bliss)
      gh_latest_release "anyvm-org/blissos-builder" || return 1
      ;;
    plan9|front9)
      gh_latest_release "anyvm-org/plan9-builder" || return 1
      ;;
    *)
      return 1
      ;;
  esac
}

if [[ $0 == *stable-vm-release.sh ]] ; then
	while [[ ( ${1} == -* ) ]] ; do shift ; done ; # ignore options
	get_stable_vm_release "${1:-}" || exit 1 ;
	exit 0;
fi ;  # else import as source

# Example usage:
# stable-vm-builder.sh freebsd && echo "OK" || echo "failed"
