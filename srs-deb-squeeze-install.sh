#!/bin/bash
# 
# A shell script that goes over the damn job to install the SunRay
# Server Software (SRS) on Ubuntu/Linux in a semi-automated fashion.
#
# Copyright (c) 2011 by Jens Langner <Jens.Langner@light-speed.de>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#
# HISTORY:
# 5.2-11.04 (10.08.2011): initial version for SRS 5.2 + Natty (11.04)
# 5.2-6.0.4 (2012-03-28): version for SRS 5.2 + Squeeze (6.0.4)
#

#################################################
# here starts the main action
#
echo "SRS Ubuntu Install Script (SRS: 5.2, Ubuntu: 11.04)"
echo "Copyright (c) Jens Langner <Jens.Langner@light-speed.de>"
echo "Modified for Debian Squeeze by Michal Jirku <box@wejn.org>"
echo "=========================================================="

# work-around for missing sudo
if command -v sudo >/dev/null 2>&1; then
	true
else
	eval 'sudo() { "$@"; }'
fi

# request the user to enter the path to the SRS install zip file
F=V26743-01.zip
[ -f "`pwd`/$F" ] && SRS_ZIP="`pwd`/$F"
[ -f "`pwd`/../$F" ] && SRS_ZIP="`pwd`/../$F"
if [ -z $SRS_ZIP ]; then
	echo -n "Please enter path of SRS 5.2 zip file (e.g. V26743-01.zip): "
	read SRS_ZIP
else
	echo "Guessed SRS 5.2 zip path: '${SRS_ZIP}'"
fi
if [ ! -f "${SRS_ZIP}" ]; then
  echo "specified install file '${SRS_ZIP}' does not exist. aborting."
  exit 0
fi

# prepare environment
sudo apt-get install -y lsb-release
sudo touch /etc/lsb-release
grep -q DISTRIB_ID=Debian /etc/lsb-release || \
	sudo sh -c 'echo "DISTRIB_ID=Debian" >> /etc/lsb-release'

# prepare dhcp server
sudo apt-get install -y dhcp3-server
if killall -0 dhcpd >/dev/null 2>&1; then
	true
else
	echo "Error: please configure dhcpd server, it won't start on its own :("
	echo "When you get it running, just restart this script to continue"
	exit 1
fi


# install additional (minimal) dependencies
sudo apt-get install -y gdm twm
cat - <<EOF > /etc/gdm/gdm.conf
[daemon]
DefaultPath=/usr/local/bin:/usr/local/sbin:/sbin:/usr/sbin:/bin:/usr/bin:/usr/bin/X11:/usr/games:/opt/SUNWut/bin
RootPath=/usr/local/bin:/usr/local/sbin:/sbin:/usr/sbin:/bin:/usr/bin:/usr/bin/X11:/usr/games:/opt/SUNWut/bin:/opt/SUNWut/sbin
PostLoginScriptDir=/etc/opt/SUNWut/gdm/SunRayPostLogin/
PreSessionScriptDir=/etc/opt/SUNWut/gdm/SunRayPreSession/
PostSessionScriptDir=/etc/opt/SUNWut/gdm/SunRayPostSession/
DisplayInitDir=/etc/opt/SUNWut/gdm/SunRayInit
XKeepsCrashing=/etc/opt/SUNWut/gdm/XKeepsCrashing.sunray

RebootCommand=
HaltCommand=
SuspendCommand=
HibernateCommand=

FlexibleXServers=0
VTAllocation=false
DynamicXServers=true
#Greeter=/usr/lib/gdm/gdmlogin

[security]
DisallowTCP=true

[xdmcp]

[gui]
GtkTheme=debian
GtkThemesToAllow=all

[greeter]
DefaultWelcome=false
Welcome=Welcome to %n
GraphicalThemes=debian-greeter
SystemMenu=true
ConfigAvailable=false
Browser=false

[chooser]

[debug]
Enable=false

[servers]
0=inactive
EOF
/etc/init.d/gdm start

# auto-accept DLJ
cat - <<EOF | sudo debconf-set-selections
sun-java6-bin	shared/accepted-sun-dlj-v1-1	boolean true
sun-java6-jdk	shared/accepted-sun-dlj-v1-1	boolean true
sun-java6-jre	shared/accepted-sun-dlj-v1-1	boolean true
EOF


# install all required packages first
echo -n "Installing required Debian packages... "
sudo apt-get install -y libldap-2.4-2 libmotif4 module-assistant tk8.4 \
	sun-java6-jre ldap-utils nscd gawk iputils-ping ksh unzip libgdbm3 \
	libx11-6 libfreetype6 libsasl2-2 libxt6 zlib1g devscripts \
	xfonts-base atftpd xfonts-100dpi xfonts-75dpi xfonts-cyrillic wget ed \
	x11-xserver-utils tcsh alien dnsutils \
	pavucontrol pavumeter paman padevchooser paprefs pulseaudio \
	pulseaudio-utils pulseaudio-module-gconf \
	pulseaudio-module-x11 libasound2-plugins gstreamer0.10-pulseaudio \
	pulseaudio-esound-compat alsaplayer-alsa

if [ `uname -m` = "x86_64" ]; then
  sudo apt-get install -y ia32-libs ia32-sun-java6-bin

  # fix-up links to libssl & libcrypto
  test -f /lib32/libcrypto.so.0.9.8 || \
	  ln -s /usr/lib32/libcrypto.so.0.9.8 /lib32/libcrypto.so.0.9.8
  test -f /lib32/libssl.so.0.9.8 || \
	  ln -s /usr/lib32/libssl.so.0.9.8 /lib32/libssl.so.0.9.8
fi

echo "ok!"

# fix-ups before SRS install
mkdir -p /tmp/SUNWut/units


######################
# lets install SRS
CD_INIT=`pwd`
TMPDIR=`mktemp -d`

# unzip the srss_*.zip file to a temporary directory
echo -n "Unzipping ${SRS_ZIP} to ${TMPDIR}... "
unzip -q ${SRS_ZIP} -d ${TMPDIR}
echo "ok!"

# convert all .rpm packages to .deb packages but make sure to ONLY convert the packages
# in the .../Packages/... directory pathes because the ones in the .../Patches/... pathes
# have to be installed afterwards.
echo -n "converting SUNW*rpm packages to .deb files..."
sudo mkdir ${TMPDIR}/packages
cd ${TMPDIR}/packages
sudo find ${TMPDIR} -name "SUNW*rpm" -path "*/Packages/*" -exec alien -d -g {} \; 2>&1 >/dev/null

# in case we are installing on a 64bit machine we need to make sure to fake the architecture
# in the generated deb files
echo -n "."
if [ `uname -m` = "x86_64" ]; then
  sudo find SUNW*-* -name control -exec sed -i "s/i386/amd64/g" {} \; 2>&1 >/dev/null
fi

# generate the .deb files now out of the directory structure the first command created
echo -n "."
sudo find SUNW*-*/ -maxdepth 0 -name "SUNW*-?.?" -exec sh -c "cd {} ; debian/rules binary-arch 2>&1 >/dev/null" \; 2>&1 >/dev/null

# delete all previously generated SUNW* directories
echo -n "."
sudo rm -rf SUNW*-?.?*
echo " ok!"

# now that we have the .deb files we go and install them
echo -n "installing SUNW*.deb packages... "
sudo dpkg -i sunw*.deb 2>&1 >/dev/null
echo "ok!"

# convert all .rpm packages from the .../Patches/... path now as they have to be installed
# AFTER the usual packages
echo -n "converting SUNW*rpm patches to .deb files..."
sudo mkdir ${TMPDIR}/patches
cd ${TMPDIR}/patches
sudo find ${TMPDIR} -name "SUNW*rpm" -path "*/Patches/*" -exec alien -d -g {} \; 2>&1 >/dev/null

# in case we are installing on a 64bit machine we need to make sure to fake the architecture
# in the generated deb files
if [ `uname -m` = "x86_64" ]; then
  sudo find SUNW*-* -name control -exec sed -i "s/i386/amd64/g" {} \; 2>&1 >/dev/null
fi

# generate the .deb files now out of the directory structure the first command created
sudo find SUNW*-*/ -maxdepth 0 -name "SUNW*-?.?" -exec sh -c "cd {} ; debian/rules binary-arch 2>&1 >/dev/null" \; 2>&1 >/dev/null

# delete all previously generated SUNW* directories
sudo rm -rf SUNW*-?.?*
echo " ok!"

# now that we have the .deb files we go and install them
echo -n "installing SUNW*.deb patches... "
sudo dpkg -i sunw*.deb 2>&1 >/dev/null
echo "ok!"

############
# now the basic installation should be fine, lets continue with patching it to
# our will

# apply our patches to the recently performed installation
echo -n "applying patches to SRS installation... "
sudo patch -d / -p0 -N -s -r - <${CD_INIT}/patches/srs.patch
sudo patch -d / -p0 -N -s -r - <${CD_INIT}/patches/kernel-modules.patch
echo "ok!"

###########
# prepare the startup script
echo -n "installing /etc/init.d/zsunray-init startup script... "
sudo cp -a ${CD_INIT}/files/zsunray-init /etc/init.d/
sudo chmod 755 /etc/init.d/zsunray-init
sudo insserv zsunray-init 2>&1 >/dev/null
echo "ok!"

###########
# prepare links to java jre
echo -n "verifying java jre install link... "
if [ ! -e "/etc/opt/SUNWut/jre" ]; then
  if [ `uname -m` = "x86_64" ]; then
    sudo ln -s /usr/lib/jvm/ia32-java-6-sun/jre /etc/opt/SUNWut
  else
    sudo ln -s /usr/lib/jvm/java-6-sun/jre /etc/opt/SUNWut
  fi
fi
echo "ok!"

###########
# make sure /var/dt exists
echo -n "verifying /var/dt exists... "
if [ ! -d "/var/dt" ]; then
  sudo mkdir -p /var/dt
fi
echo "ok!"

###########
# link the global xkb settings into SRS
echo -n "patching XKB installation for SRS compatibility... "
if [ ! -e "/opt/SUNWut/lib/xkb/xkbcomp" ]; then
  sudo cp -a /opt/SUNWut/lib/xkb /opt/SUNWut/lib/xkb.bak
  sudo mv /usr/share/X11/xkb /usr/share/X11/xkb.bak
  sudo cp -an /usr/share/X11/xkb.bak/* /opt/SUNWut/lib/xkb/
  sudo rm -rf /opt/SUNWut/lib/xkb/compiled
  sudo ln -s /var/lib/xkb /opt/SUNWut/lib/xkb/compiled
  sudo ln -s /usr/bin/xkbcomp /opt/SUNWut/lib/xkb/xkbcomp
  sudo ln -s /opt/SUNWut/lib/xkb /usr/share/X11/
fi
echo "ok!"

###########
# build the required kernel modules and install them
echo -n "building/installing SRS kernel modules... "
sudo m-a -t prepare 2>&1 /dev/null
sudo make -C /usr/src/SUNWut/utadem clean default install 2>&1 >/dev/null
sudo make -C /usr/src/SUNWut/utio clean default install 2>&1 >/dev/null
sudo make -C /usr/src/SUNWut/utdisk clean default install 2>&1 >/dev/null
sudo depmod -a
echo "ok!"

###########
# start utsyscfg to let it create some links and stuff
echo -n "starting up 'utsyscfg' to generate links... "
sudo /etc/init.d/utsyscfg start 2>&1 >/dev/null
sudo /etc/init.d/utsyscfg stop 2>&1 >/dev/null
echo "ok!"

###########
# link libutdev.so.1 into /usr/lib to have USB mounting working properly 
echo -n "verifying /usr/lib/libutdev.so.1 exists... "
if [ ! -e "/usr/lib/libutdev.so.1" ]; then
  sudo ln -s /opt/SUNWut/lib/libutdev.so.1 /usr/lib/
fi
echo "ok!"

###########
# make sure we are having certain 32bit compatible libs installed which
# SRS requires for proper operation
echo -n "verifying/installing required 32bit libraries... "
if [ `uname -m` = "x86_64" ]; then
  # not all required 32bit libraries exist as ia32 packages
  # Thus, we go and extract them from ubuntu 8.10 (i386) deb packages
  sudo cp -a ${CD_INIT}/lib/libXm.so.3* /opt/SUNWut/lib/
  sudo cp -a ${CD_INIT}/lib/libXfont.so.1* /opt/SUNWut/lib/
  sudo cp -a ${CD_INIT}/lib/libfontenc.so.1* /opt/SUNWut/lib/
  sudo cp -a ${CD_INIT}/lib/libglib-1.2.so.0* /opt/SUNWut/lib/

  if [ ! -e "/usr/lib32/libXm.so.3" ]; then
    sudo ln -s /opt/SUNWut/lib/libXm.so.3 /usr/lib32/
  fi
fi
echo "ok!"

###########
# generate the compatlinks of SRSS 
echo -n "letting SRS create compatibility links... "
sudo /opt/SUNWut/lib/utctl.d/features/utcompatlinksctl enable
sudo ldconfig
echo "ok!"

###########
# install the supplied version of tomcat 5 
echo -n "verifying apache-tomcat installation... "
if [ ! -e "/opt/apache-tomcat-5.5.20" ]; then
  cd ${TMPDIR}
  sudo tar -xzf srs_5.2/Supplemental/Apache_Tomcat/apache-tomcat-5.5.20.tar.gz 2>&1 >/dev/null
  sudo mv ${TMPDIR}/apache-tomcat-5.5.20 /opt/
  sudo ln -sf /opt/apache-tomcat-5.5.20 /opt/apache-tomcat
  cd ${CD_INIT}
fi
echo "ok!"

###########
# add stuff to Xsession.d which is required for proper SRSS
# operation
echo -n "installing Xsession.d startup files... "
sudo cp -a ${CD_INIT}/files/10SUNWut /etc/X11/Xsession.d/
sudo cp -a ${CD_INIT}/files/66SUNW-pulseaudio /etc/X11/Xsession.d/
sudo cp -a ${CD_INIT}/files/20x11-common_process-args /etc/X11/Xsession.d/
echo "ok!"

###########
# cleanup TEMPDIR
echo -n "cleaning up ${TMPDIR}... "
sudo rm -rf ${TMPDIR}
echo "ok!"

###########
# manual configure SRSS
sudo /opt/SUNWut/sbin/utconfig
sudo /opt/SUNWut/sbin/utpolicy -a -m -z both -g -u both
sudo /opt/SUNWut/sbin/utadm -L on
sudo /opt/SUNWut/sbin/utstart -c

# enable xkb & xrender
sudo /opt/SUNWut/bin/utxconfig -a -k on
sudo /opt/SUNWut/bin/utxconfig -a -n on

# fix up tags in "utsvtreg"
sudo cp ${CD_INIT}/files/utsvtreg /etc/init.d/
sudo chmod 755 /etc/init.d/utsvtreg

###########
# installation finished!
echo "installation finished!"

cat - <<EOF


You will probably want to use something like:

/opt/SUNWut/sbin/utadm -a eth0

to add interface. And then:

/etc/init.d/zsunray-init restart
EOF

exit 0
