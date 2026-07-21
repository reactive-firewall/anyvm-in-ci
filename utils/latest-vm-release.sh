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

test -x "$(command -v awk)" || exit 126 ;
test -x "$(command -v curl)" || test -x "$(command -v wget)" || exit 126 ;
test -x "$(command -v head)" || exit 126 ;
test -x "$(command -v sed)" || exit 126 ;
test -x "$(command -v sort)" || exit 126 ;
test -x "$(command -v tail)" || exit 126 ;
test -x "$(command -v tr)" || exit 126 ;

# get_latest_vm_release NAME
# Portable /bin/sh-compatible function returning a single token: the latest
# "default" release/series for NAME (one of the supported values).
# Exits non‑zero and prints nothing on unknown NAME or failure.
# Uses curl or wget (whichever exists) and standard POSIX tools only.
get_latest_vm_release() {
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

  # sort_versions: portable replacement for `sort -V`
  # Usage: sort_versions < file
  #        printf '%s\n' a b c | sort_versions

  sort_versions() {
    # We tag each record with its original line, then sort by a
    # locale-independent “version key”.
    # The version key is built as a sequence of:
    #   - non-digit segments: "-" + uppercase chars
    #   - digit runs:          zero-padded numeric value + length marker
    #
    # This is a “best-effort” mimic of sort -V ordering:
    #   • numeric runs compared by numeric value
    #   • non-numeric parts compared lexicographically
    #   • shorter length numeric runs (e.g., "1" vs "001") still compare equal numerically

    awk '
    function upcase(s,  i, c, o) {
      o = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c >= "a" && c <= "z") c = sprintf("%c", ord = index("abcdefghijklmnopqrstuvwxyz", substr(c,1,1)) ? ord : 0)
        # simpler: ASCII math
        if (substr(c,1,1) >= "a" && substr(c,1,1) <= "z") {
          c = sprintf("%c", ord(substr(c,1,1)) - 32)
        }
        o = o c
      }
      return o
    }
    # portable ord()
    function ord(ch,  code) { code = sprintf("%d", substr(ch,1,1)); return code }

    function makekey(s,   i, n, ch, isdig, buf, seg, out, len, num, pad) {
      out = ""
      n = length(s)
      i = 1
      while (i <= n) {
        ch = substr(s, i, 1)
        isdig = (ch ~ /[0-9]/)

        if (isdig) {
          j = i
          while (j <= n && substr(s, j, 1) ~ /[0-9]/) j++
          seg = substr(s, i, j - i)          # digit run
          len = length(seg)

          # Strip leading zeros for numeric comparison,
          # but keep length marker to stabilize equal values.
          sub(/^0+/, "", seg)
          if (seg == "") seg = "0"
          # Pad numeric string to fixed width using length of original run.
          # For portability, we avoid big integers and compare by (trimmed numeric, len).
          # Use two fields:
          #   field A: trimmed numeric right-padded to 20 (cap) with spaces
          #   field B: length of trimmed numeric
          # Cap to 20 chars to keep key bounded; for longer numbers,
          # lexicographic of trimmed digits still works if lengths match.
          if (length(seg) > 20) {
            pad = substr(seg, 1, 20)
            out = out "D" pad "L" sprintf("%06d", length(seg))
          } else {
            out = out "D" sprintf("%020s", seg) "L" sprintf("%06d", length(seg))
          }

          # length of original digit run as a tie-breaker (closer to sort -V stability)
          out = out "O" sprintf("%06d", len)
          i = j
        } else {
          # non-digit run: compare lexicographically
          j = i
          while (j <= n && substr(s, j, 1) !~ /[0-9]/) j++
          seg = substr(s, i, j - i)

          # Uppercase for more consistent cross-platform behavior
          # (sort -V effectively treats bytes; we normalize case to reduce variance)
          # Convert ASCII letters to uppercase; leave others.
          for (k = 1; k <= length(seg); k++) {
            c = substr(seg, k, 1)
            if (c >= "a" && c <= "z") c = sprintf("%c", ord(c) - 32)
            out = out "T" c
          }
          i = j
        }
      }
      return out
    }

    {
      line = $0
      # Build a key; prefix with a field separator that sorts before digits/letters.
      key = makekey(line)
      # Emit: key<TAB>original line
      print key "\t" line
    }
    ' | sort -t "$(printf '\t')" -k1,1 | cut -f2-
  }

  case "$name" in
    freebsd)
      # Use official release directory listing; pick highest dotted release
      fetch "https://www.freebsd.org/releng/" |
        awk '
          {
            # try "FreeBSD X.Y"
            if (match($0, "FreeBSD[[:space:]]+[0-9]+\\.[0-9]+")) {
              print substr($0, RSTART + 8, RLENGTH - 8)
            }
            # try "/releases/X.Y/"
            if (match($0, "/releases/[0-9]+\\.[0-9]+")) {
              print substr($0, RSTART + 10, RLENGTH - 10)
            }
            # try "X.Y-RELEASE"
            if (match($0, "[0-9]+\\.[0-9]+-RELEASE")) {
              print substr($0, RSTART, RLENGTH - 8)
            }
          }
        ' |
        awk '!seen[$0]++{print}' |    # dedupe while preserving portability
        sort_versions |
        tail -n2 | head -n1 || return 1  # use penultimate - skip latest Dev branch
      ;;
    ghostbsd)
      test -x "$(command -v jq)" || return 126 ;
      # GhostBSD releases listed on GitHub releases page
      fetch "https://api.github.com/repos/ghostbsd/ghostbsd/branches" |
        jq -r '.[].name' |
        grep '^stable/' |
        sed 's|^stable/||' |
        sort_versions |
        tail -n1 || return 1
      ;;
    openbsd)
      # OpenBSD publishes "www.openbsd.org/faq/faq4.html" with current version string
      fetch "https://www.openbsd.org/" |
        tr '\n' ' ' |
        sed -n 's/.*[Cc]urrent release is[^>]*>[^>]*OpenBSD[[:space:]]*\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' |
        sort_versions |
        head -n1 || return 1
      ;;
    netbsd)
      # NetBSD release page contains "NetBSD X.Y" in title or headings
      fetch "https://netbsd.org/" |
        tr '\n' ' ' |
        grep -oEi 'NetBSD[ _-]?[0-9]+\.[0-9]+|/releases/[0-9]+\.[0-9]+' |
        sed -E 's#.*/releases/([0-9]+\.[0-9]+).*#\1#; s/.*[Nn]et[Bb][Ss][Dd][ _-]?([0-9]+\.[0-9]+).*/\1/' |
        sort_versions | uniq | tail -n1 || return 1
      ;;
    dragonflybsd|dragonfly)
      # DragonFly release info on homepage
      fetch "https://www.dragonflybsd.org/" |
        grep -oEi 'DragonFly[ _-]?[0-9]+\.[0-9]+|/releases/[0-9]+\.[0-9]+' |
        sed -E 's#.*/releases/([0-9]+\.[0-9]+).*#\1#; s/.*[Dd]ragon[Ff]ly[ _-]?([0-9]+\.[0-9]+).*/\1/' |
        ( sort_versions 2>/dev/null || sort ) | uniq | tail -n1 || return 1
      ;;
    midnightbsd|midnight)
      # MidnightBSD latest stable on homepage or releases
      fetch "https://www.midnightbsd.org/" |
        tr '\n' ' ' |
        grep -oEi 'Midnight[Bb][Ss][Dd][- _]*[0-9]+(\.[0-9]+)*' |
        sed -E 's/.*[Mm]idnight[Bb][Ss][Dd][- _]*([0-9]+(\.[0-9]+)*).*/\1/' |
        awk '!seen[$0]++{print}' |
        sort_versions | tail -n1 || return 1
      ;;
    solaris)
      # Oracle Solaris 11/12 naming — prefer "11" or "11.4" if present on page
      fetch "https://www.oracle.com/solaris/" |
        tr '\n' ' ' |
        sed 's/</\n</g' |
        grep -i -m1 -oE 'Solaris[[:space:]]*([0-9]+(\.[0-9]+)?)' |
        sed -E 's/.*[Ss]olaris[[:space:]]*//' |
        head -n1 || return 1
      ;;
    omnios)
      # OmniOS uses releases like "omnios-rVVxxyy"
      # can look for LTS versions on download.html page: pattern is https://downloads.omnios.org/media/lts/omnios-r${VERSION}r.iso
      # circa may 4 2026 is "r151058"
      fetch "https://www.omnios.org/download.html" |
        tr '\n' ' ' |
        grep -oEi 'omnios-r[0-9]{6}[r]?\.iso' | grep -oEi 'omnios-r[0-9]{6}[r]?' |
        sed -E 's/.*r([0-9]{6}).*/\1/' | sort_versions |
        head -n1 || return 1
      ;;
    openindiana)
      # OpenIndiana Hipster has versions like "Hipster-YYYY.MM"
      fetch "https://www.openindiana.org/" |
        sed -n 's/.*[- ]\([0-9][0-9][0-9][0-9]\.[0-9][0-9]\).*/\1/p' |
        sort_versions |
        head -n1 || return 1
      ;;
    tribblix)
      # Tribblix releases listed on GitHub (in tribblix-releases repo as folders) or site?
      printf 'm%1i' "40" ; # circa arpil 2026 - milestone 40
#      fetch "https://www.tribblix.org/" |
#        tr '\n' ' ' |
#        grep -oEi 'tribblix[-_ ]?[0-9]+(\.[0-9]+)*|/releases/[0-9]+(\.[0-9]+)*' |
#        sed -E 's#.*/releases/([0-9.]+).*#\1#; s/.*tribblix[-_ ]?([0-9.]+).*/\1/' |
#        ( sort -V 2>/dev/null || sort ) | uniq | tail -n1 || return 1
      ;;
    haiku)
      # Haiku releases use "version" like "r1beta1" — attempt to get latest branch via GitHub API
      test -x "$(command -v jq)" || return 126 ;
      fetch "https://api.github.com/repos/haiku/haiku/branches" | jq -r '.[].name' |
        grep '^r.*' | sort | tail -n1 || return 1
      ;;
    hurd)
      # pattern: (:?[Hh]{1}[u]{1}[r]{1}[d]{1}\-)\d\.\d(:?\.tar)
      fetch "https://ftp.gnu.org/gnu/hurd/" 2>/dev/null |
        grep -oEe "[Hh]{1}[u]{1}[r]{1}[d]{1}\-\d\.\d\.tar" |
        grep -oEe "\d\.\d" | sort_versions |
        tail -n1 || return 1
      ;;
    ubuntu)
      # Ubuntu publishes current LTS and interim names on releases.ubuntu.com
      fetch "https://changelogs.ubuntu.com/meta-release" |
        sed -n 's/^Version: //p' | cut -d\  -f1-1 | sort_versions |
        tail -n1 || return 1
      ;;
    blissos|bliss)
      # BEST-EFFORT attempt only (there is missing support in anyvm builder circa july 2026)
      # version 16 was typhoon-x86 (only known supported varient by builder 2.0.2)
      # version 17 was universe-x86
      # version 18 is voyager-x86
      # project moved github org after version 15 (from project BlissRoms-x86/manifest)
      # to a new github org starting with 16 (to current project BlissOS/platform_manifest)
      # Bliss OS releases on GitHub; use latest release branch
      test -x "$(command -v jq)" || return 126 ;
      { { fetch "https://api.github.com/repos/BlissRoms-x86/manifest/branches" 2>/dev/null |
          jq -r '.[].name' ;} 2>/dev/null;
        { fetch "https://api.github.com/repos/BlissOS/platform_manifest/branches" 2>/dev/null |
          jq -r '.[].name' ;} 2>/dev/null ;} |
        grep '.*-x86' | tail -n1 || return 1
      ;;
    plan9|front9)
      # the last release of Plan-9 was version 4 and was re-released under MIT License terms before
      # July 2026 according to:
      # http://ftp.osuosl.org/pub/plan9/history/plan9-4e-latest.iso.bz2
      # But anyvm uses Front9 as plan9 which is what we can check here (INSECURE):
      fetch "http://www.9front.org/releases/" 2>/dev/null | grep -Ee "releases\/20\d+" 2>/dev/null |
        grep -oEe "2\d{3}" 2>/dev/null |
        sort_versions |
        tail -n1 || return 1
      ;;
    *)
      return 1
      ;;
  esac
}

if [[ $0 == *latest-vm-release.sh ]] ; then
    while [[ ( ${1} == -* ) ]] ; do shift ; done ; # ignore options
    get_latest_vm_release "${1:-}" || exit 1 ;
    exit 0;
fi ;  # else import as source

# Example usage:
# latest-vm-release.sh freebsd && echo "OK" || echo "failed"
