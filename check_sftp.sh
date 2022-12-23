#!/bin/bash
################################################################################
# Script:       check_sftp.sh                                                  #
# Author:       Claudio Kuenzler www.claudiokuenzler.com                       #
# Purpose:      Monitor SFTP server (connection, upload, download)             #
# Repository:   https://github.com/Napsty/check_sftp                           #
# License:      GPLv3 (see LICENSE file in same git repository                 #
#                                                                              #
# GNU General Public Licence (GPL) http://www.gnu.org/                         #
# This program is free software; you can redistribute it and/or                #
# modify it under the terms of the GNU General Public License                  #
# as published by the Free Software Foundation, either version 3               #
# of the License, or (at your option) any later version.                       #
#                                                                              #
# This program is distributed in the hope that it will be useful,              #
# but WITHOUT ANY WARRANTY; without even the implied warranty of               #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                #
# GNU General Public License for more details.                                 #
#                                                                              #
# You should have received a copy of the GNU General Public License            #
# along with this program; if not, see <https://www.gnu.org/licenses/>.        #
#                                                                              #
# Copyright 2022 Claudio Kuenzler                                              #
#                                                                              #
# History/Changelog:                                                           #
# 20221223 1.0.0: Public release                                               #
# 20221223 1.0.1: Add private key authentication with passphrase (issue #1)    #
################################################################################
#Variables and defaults
version=1.0.1
STATE_OK=0              # define the exit code if status is OK
STATE_WARNING=1         # define the exit code if status is Warning
STATE_CRITICAL=2        # define the exit code if status is Critical
STATE_UNKNOWN=3         # define the exit code if status is Unknown
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin # Set path
port=22
user=$USER
directory=monitoring
tmpdir=/tmp
verbose=false
sftpoptions="-o StrictHostKeyChecking=no "
################################################################################
#Functions
help () {
echo -e "$0 $version (c) 2022 Claudio Kuenzler and contributors (open source rulez!)

Usage: ./check_sftp.sh -H SFTPServer [-P port] [-u username] [-p password] [-i privatekey] [-o options] [-d remotedir] [-t tmpdir] [-v]

Options:

   *  -H Hostname or ip address of SFTP Server
      -P Port (default: 22)
      -u Username (default: \$USER from environment)
      -p Password
      -i Identity file/Private Key for Key Authentication (example: -i '~/.ssh/id_rsa')
      -o Additional SSH options (-o ...) to be added (example: -o '-o StrictHostKeyChecking=no')
      -d Remote directory to use for upload/download (default: monitoring)
      -t Local temp directory (default: /tmp)
      -v Verbose mode (shows sftp commands and output)
      -h Shows this help

*mandatory options

Requirements: sftp, sshpass (when using a password)"
exit $STATE_UNKNOWN;
}
################################################################################
# Check for people who need help - aren't we all nice ;-)
if [ "${1}" = "--help" -o "${#}" = "0" ]; then help; exit $STATE_UNKNOWN; fi
################################################################################
# Get user-given variables
while getopts "H:P:u:p:i:o:d:vh" Input
do
  case ${Input} in
  H)      host=${OPTARG};;
  P)      port=${OPTARG:=22};;
  u)      user=${OPTARG};;
#  p)      export SSHPASS="${OPTARG}"; usepass="sshpass -e "; sftpoptions+="-o PubkeyAuthentication=no -o BatchMode=no ";;
  p)      export SSHPASS="${OPTARG}"; usepass="sshpass -e ";;
  #i)      keyfile="${OPTARG}"; identityfile="-i ${OPTARG}";;
  i)      keyfile="${OPTARG}";;
  o)      sftpoptions+="${OPTARG} ";;
  d)      directory=${OPTARG:="monitoring"};;
  t)      tmpdir=${OPTARG:=/tmp};;
  v)      verbose=true;;
  *)      help;;
  esac
done
################################################################################
# Input checks and requirements
for cmd in sftp; do
  if ! `which ${cmd} >/dev/null 2>&1`; then
    echo "CHECK_SFTP UNKNOWN: ${cmd} does not exist, please check if command exists and PATH is correct"
    exit ${STATE_UNKNOWN}
  fi
done

if [[ -n ${usepass} ]]; then
  if ! `which sshpass >/dev/null 2>&1`; then
    echo "CHECK_SFTP UNKNOWN: command 'sshpass' does not exist, please check if command exists and PATH is correct"
    exit ${STATE_UNKNOWN}
  fi
fi

if [[ -z ${host} ]]; then
  echo "CHECK_SFTP UNKNOWN: Missing SFTP Host (-H)"
  exit ${STATE_UNKNOWN}
fi

if [ "${verbose}" = true ]; then
  stdoutredir="/dev/stderr"
else
  stdoutredir='/dev/null'
fi

# When using key authentication, add SSH key to ssh-agent
if [[ -n "${keyfile}" ]]; then
  identityfile="-i ${keyfile}"
  usepass=""
  ssh-add -l 2>/dev/null
  agentrc=$?
  if [[ ${agentrc} -gt 0 ]]; then
    eval "$(ssh-agent)" > /dev/null
    trap 'ssh-agent -k > /dev/null' EXIT
    echo "exec cat" > ${tmpdir}/check_sftp_ap.sh
    chmod 755 ${tmpdir}/check_sftp_ap.sh
    export DISPLAY=1
    echo "${SSHPASS}" | SSH_ASKPASS=${tmpdir}/check_sftp_ap.sh ssh-add ${keyfile} >/dev/null 2>&1
    rm -f ${tmpdir}/check_sftp_ap.sh
  fi
fi

# When using password authentication, add special SSH options
if [[ -n "${usepass}" ]] && [[ -z "${keyfile}" ]]; then
  sftpoptions+="-o PubkeyAuthentication=no -o BatchMode=no "
fi
################################################################################
# Create a local file with current timestamp
ts=$(date +%s)
file=mon.${ts}
touch ${tmpdir}/${file}

# Establish connection and make sure the directory exists on the SFTP server
${usepass} sftp -P ${port} ${identityfile} ${sftpoptions} -b - ${user}@${host} <<EOF >${stdoutredir} 2>&1
cd ${directory}
exit
EOF

# Handle exit code from sftp above
# 0: All worked
# 1: Directory does not exist
# 127: Permission denied (likely related to publickey)
# 255: SFTP connection failed
exitcode=$?

# Communication failed, alert and exit
if [[ ${exitcode} -eq 255 ]]; then 
	echo "CHECK_SFTP CRITICAL: Unable to establish a connection to SFTP server with given credentials"
	exit $STATE_CRITICAL
fi

if [[ ${exitcode} -eq 127 ]]; then 
	echo "CHECK_SFTP CRITICAL: Unable to establish a connection to SFTP server with given credentials"
	exit $STATE_CRITICAL
fi

if [[ ${exitcode} -gt 1 ]]; then 
	echo "CHECK_SFTP CRITICAL: Unable to establish a connection to SFTP server with given credentials"
	exit $STATE_CRITICAL
fi

# Create directory if not exists
if [[ ${exitcode} -eq 1 ]]; then
	createdircmd="mkdir ${directory}"
fi

# Continue with check
${usepass} sftp -P ${port} ${identityfile} ${sftpoptions} -b - ${user}@${host} <<EOF >${stdoutredir} 2>&1
${createdircmd}
cd ${directory}
lcd ${tmpdir}
put ${tmpdir}/${file}
get ${file}
rm ${file}
exit
EOF

exitcode=$?

case "${exitcode}" in
  0) output="CHECK_SFTP OK: Communication to ${host} worked. Upload, Download and Removal of file (${file}) into/from remote directory (${directory}) worked."
     exitcode=${STATE_OK}
     ;; 
  1) output="CHECK_SFTP WARNING: At least one of the SFTP commands (cd/put/get) failed."
     exitcode=${STATE_WARNING}
     ;; 
  *) output="CHECK_SFTP CRITICAL: Unknown error."
     exitcode=${STATE_CRITICAL}
     ;; 
esac

# Remove local files
rm -f ${file}
rm -f ${tmpdir}/${file}

# Some performance data because graphs are nice to look at
duration=$(( $(date +%s) - ${ts} ))

echo "${output}|checktime=${duration}s;;;;"
exit ${exitcode}
