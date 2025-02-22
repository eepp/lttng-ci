#!/usr/bin/python3
# Copyright (C) 2018 - Jonathan Rajotte-Julien <jonathan.rajotte-julien@efficios.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

import argparse
import gzip
import os
import shutil
import subprocess
import sys

from datetime import datetime


def compress(filename):
    command = [
        'tar', '-c', '-z',
        '-f', filename + ".tar.gz",
        '-C', filename,
        './'
    ]
    subprocess.run(command, check=True)
    shutil.rmtree(filename)


packages = [
    'autoconf',
    'automake',
    'bash-completion',
    'bison',
    'build-essential',
    'chrpath',
    'clang',
    'cloc',
    'curl',
    'elfutils',
    'flex',
    'gettext',
    'git',
    'htop',
    'jq',
    'libarchive-tools',
    'libdw-dev',
    'libelf-dev',
    'libffi-dev',
    'libglib2.0-dev',
    'libmount-dev',
    'libnuma-dev',
    'libpfm4-dev',
    'libpopt-dev',
    'libtap-harness-archive-perl',
    'libtool',
    'libxml2',
    'libxml2-dev',
    'netcat-traditional',
    'openssh-server',
    'psmisc',
    'python3-virtualenv',
    'python3',
    'python3-dev',
    'python3-numpy',
    'python3-pandas',
    'python3-pip',
    'python3-setuptools',
    'python3-sphinx',
    'stress',
    'swig',
    'texinfo',
    'tree',
    'uuid-dev',
    'vim',
    'wget',
]


def main():
    parser = argparse.ArgumentParser(description='Generate lava lttng rootfs')
    parser.add_argument("--arch", default='amd64')
    parser.add_argument("--distribution", default='jammy')
    parser.add_argument("--mirror", default='http://archive.ubuntu.com/ubuntu')
    parser.add_argument(
        "--component", default='universe,multiverse,main,restricted')
    args = parser.parse_args()

    name = "rootfs_{}_{}_{}".format(args.arch, args.distribution,
                                        datetime.now().strftime("%Y-%m-%d"))

    hostname = "linaro-server"
    user = "linaro/linaro"
    root_password = "root"
    print(name)
    command = [
        "debootstrap",
        "--arch={}".format(args.arch),
        "--components={}".format(args.component),
        "--verbose",
        args.distribution,  # SUITE
        name,  # TARGET (directory is created)
        args.mirror,  # MIRROR
    ]
    completed_command = subprocess.run(command, check=True)

    # packages
    command = [
        'chroot', name,
        'apt-get', 'install', '-y', ] + packages
    completed_command = subprocess.run(command, check=True)

    # hostname
    with open(os.path.join(name, 'etc', 'hostname'), 'w', encoding='utf-8') as f:
        f.write(hostname + "\n")

    # user
    command = [
        'chroot', name,
        'adduser', '--gecos', '', '--disabled-password', 'linaro',
    ]
    completed_process = subprocess.run(command, check=True)

    command = [
        'chroot', name, 'chpasswd',
        ]
    process = subprocess.Popen(command, stdin=subprocess.PIPE, text=True)
    process.communicate(input='linaro:linaro')

    # root password
    process = subprocess.Popen(command, stdin=subprocess.PIPE, text=True)
    process.communicate(input="root:root")

    compress(name)


if __name__ == "__main__":
    if os.getuid() != 0:
        print("This script should be run as root: this is required by deboostrap", file=sys.stderr)
        sys.exit(1)
    main()
