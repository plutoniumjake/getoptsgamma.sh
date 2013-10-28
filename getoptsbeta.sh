#!/bin/bash
# getopts.sh
# get server configs and dump to files / folders on backup drive
# script by abrevick@liquidweb.com
# contributions by dbigelow and jvandeventer
VERSION="2.0 beta"

settinthevars () {
#set directory where saved content will go:
DIR="/backup/server.configs"
BACKDIR=${DIR}/backups
#rsync these files/dirs
#lots pulled from /scripts/cpbackup, possibly some redundancy
FILES="
/etc/cpbackup.conf
/etc/cron*
/etc/exim.conf
/etc/exim.conf.local
/etc/exim.conf.localopts
/etc/fstab
/etc/group
/etc/hosts
/etc/httpd/conf/httpd.conf
/etc/ips
/etc/ips.remotedns
/etc/ips.remotemail
/etc/localdomains
/etc/master.passwd
/etc/modprobe.conf
/etc/my.cnf
/etc/namedb
/etc/named.conf
/etc/passwd
/etc/proftpd
/etc/proftpd.conf
/etc/quota.conf
/etc/rc.conf
/etc/remotedomains
/etc/reservedipreasons
/etc/reservedips
/etc/rndc.conf
/etc/secondarymx
/etc/shadow
/etc/ssl
/etc/sysconfig/network-scripts
/etc/userdomains
/etc/valiases
/etc/vdomainaliases
/etc/vfilters
/etc/wwwacct.conf
/root/.my.cnf
/usr/local/apache/conf
/usr/local/cpanel/3rdparty/interchange/interchange.cfg
/usr/local/cpanel/3rdparty/mailman
/usr/local/frontpage
/usr/local/lib/php.ini
/usr/share/ssl
/var/cpanel
/var/cron/tabs
/var/lib/named/chroot/var/named/master
/var/lib/rpm
/var/log/bandwidth
/var/named
/var/spool/cron
/var/spool/fcron
/var/ssl
"
#hardware vars
CPU=$(cat /proc/cpuinfo | grep "model name" | uniq | cut -d: -f2)
MEM=$(cat /proc/meminfo | grep MemTotal | sed 's/ //g' | cut -d: -f2)
#FS=$(df -h) 			not using currently as it will not format properly
#MOUNT=$(mount | column -t) 	not using currently as it will not format properly
#test for raid
if [[ $(lspci | grep -i raid 2> /dev/null) ]] 
	then
		RAID=$(lspci | grep -i raid | cut -d: -f3)
	else
		RAID=None
fi
#OS
OS=$(cat /etc/redhat-release)
KERNEL=$(uname -a)
#network vars
MAINIP=$(grep ADDR /etc/wwwacct.conf | awk '{print $2}')
DEDIP=$(/scripts/ipusage | tail -n1 | awk '{print $1,$3}' | cut -d] -f1)
#apache vars
HTTPV=$(/usr/local/apache/bin/httpd -v | grep version | cut -d"/" -f2 | cut -d" " -f1)
HTTPMPM=$(/usr/local/apache/bin/httpd -V | grep -i "server mpm" | awk '{print $3}')
HTTPMOD=$(/usr/local/apache/bin/httpd -l | tail -n +2)
#PHP vars
PHPVER=$(php -i | grep -i "php version" | head -n 1 | cut -d">" -f2)
PHPLOC=$(php -i | grep php.ini | grep "Configuration" | cut -d ">" -f2 | cut -c 2- | tail -n 1)
PHPREG=$(egrep -i "\<register_globals\> \=" ${PHPLOC})
PHPMEM=$(egrep -i "^memory_limit" ${PHPLOC} | cut -d";" -f1)
PHPMAXEX=$(egrep -i "^max_execution_time" ${PHPLOC} | cut -d";" -f1)
PHPMAXIN=$(egrep -i "^max_input_time" ${PHPLOC} | cut -d";" -f1)
PHPERRORS=$(egrep -i "^error_reporting" ${PHPLOC})
PHPINCLUDE=$(egrep -i "^include_path" ${PHPLOC} | cut -d= -f2)
SUEXEC=$( /usr/local/cpanel/bin/rebuild_phpconf --current | tail -n2 | head -n1 | awk '{print $2}')
PHPHAND=$(/usr/local/cpanel/bin/rebuild_phpconf --current | tail -n +2 | awk -F: '{print $2}' | sed 's/^\ //' | tr '\n' ' ' | if [[ "${SUEXEC}" == "enabled" ]]; then awk '{print $1" "$2" "$3" 1"}'; else awk '{print $1" "$2" "$3" 0"}'; fi)
#mysql vars
MYSQLV=$(mysql --version | cut -d" " -f6 | sed s/,//)
MYSQLDATA=$(mysql -NB -e "show variables like 'datadir'" | awk '{print $2}')
MYSQLSTAT=$(mysqladmin stat)
DBS=$(mysql -Ns -e "show databases" | egrep -v "information_schema|cphulkd|eximstats|horde|leechprotect|modsec|mysql|roundcube|^test$")
#GRANTS=$(mysql -B -N -e "SELECT DISTINCT CONCAT('SHOW GRANTS FOR ''', user, '''@''', host, ''';') AS query FROM mysql.user" | egrep -v '(root|horde|cphulkd|eximstats|modsec|roundcube|liquidweb.com)' | mysql $@ | sed 's/\(GRANT .*\)/\1;/;s/^\(Grants for .*\)/## \1 ##/;/##/{x;p;x;}')  not using currently as it will not format properly
#perl vars
PERLV=$(perl -v | tail -n +2 | head -1 | awk '{print $4}' | cut -c2-)
#cpanel vars
CPANV=$(cat /usr/local/cpanel/version)
CPANPHPLOADER=$(grep -i phploader /var/cpanel/cpanel.config | cut -d"=" -f2)
ALLUSERS=$(/bin/ls -A1 /var/cpanel/users | grep -v system)
CPUSERSPATH=/var/cpanel/users

#weee colors
HEADER="\e[1;33m===== TEXT =====\e[0m"
INSTALLED="[\e[0;32mINSTALLED\e[0m]"
NOTFOUND="[\e[0;31mNOT FOUND\e[0m]"
CATEGORY="\e[0;36mTEXT => \e[0m"
}

#Generic function for a y/n question
query () {
if [ "$force" == "yes" ]; then 
	SUBLOOP=1
	echo "--forced"
else
	SUBLOOP=0
	while [ $SUBLOOP -eq 0 ];
		do
		read -p "(yes/no) " yesno
		case $yesno in
			y|yes)
				SUBLOOP=1;
				;;
			n|no)
				exit 1;
				;;
			*)
			echo "You must enter 'yes' or 'no'"
			SUBLOOP=0
			;;
		esac
	done
fi
}

yesorno () {
if [ "$force" == "yes" ]; then
	return 0
	echo "--forced"
else
	while true; 
		do
		read -p "$* (y/n)? " yn
		case $yn in
			yes|Yes|YES|y|Y)
			return 0  ;;
			no|No|n|N|NO)
			return 1  ;;
			*)
			echo "Please answer 'y' or 'n'."
		esac
	done
fi
}
 
#get server settings
serverinfo () {
        echo -e "\n${HEADER/TEXT/Server Information}\n"
	echo -e "${CATEGORY/TEXT/Hostname} $(hostname)"
	echo -e "${CATEGORY/TEXT/OS} ${OS}"
#print hardware info
	echo -e "${CATEGORY/TEXT/CPU}${CPU}"
	echo -e "${CATEGORY/TEXT/Memory} ${MEM}"
	echo -e "${CATEGORY/TEXT/Partitions}"
	df -h
	echo -e "${CATEGORY/TEXT/Mounts}"
	mount | column -t
	echo -e "${CATEGORY/TEXT/RAID} ${RAID}"
	echo -e "${CATEGORY/TEXT/Kernel} ${KERNEL}"
#print IP info
	echo -e "${CATEGORY/TEXT/Main IP} ${MAINIP}"
	echo -e "${CATEGORY/TEXT/Dedicated IPs}\n" ${DEDIP}
#print cpanel info
	echo -e "${CATEGORY/TEXT/Cpanel version} ${CPANV}"
	echo -e "${CATEGORY/TEXT/Cpanel PHP} ${CPANPHPLOADER}"
}
 
phpopts () {
        echo -e "\n${HEADER/TEXT/PHP}\n"
	echo -e "${CATEGORY/TEXT/PHP Version} ${PHPVER}"
	echo -e "${CATEGORY/TEXT/Main php.ini} ${PHPLOC}"
	echo -e "${CATEGORY/TEXT/Include path}${PHPINCLUDE}"
	echo -e "${CATEGORY/TEXT/Reg Globals Line}${PHPREG}"
	echo -e "${CATEGORY/TEXT/Mem Limit} ${PHPMEM}"
	echo -e "${CATEGORY/TEXT/Max In Time} ${PHPMAXIN}"
	echo -e "${CATEGORY/TEXT/Max Ex Time} ${PHPMAXEX}"
	echo -e "${CATEGORY/TEXT/Error Reporting} ${PHPERRORS}"
	echo -e "${CATEGORY/TEXT/cPanel PHP Loader} ${CPANPHPLOADER}"
        echo -e "${HEADER/TEXT/PHP HANDLER INFORMATION}\n"
	/usr/local/cpanel/bin/rebuild_phpconf --current
	echo -e "\nMatch php handler with the following line:"
	echo "/usr/local/cpanel/bin/rebuild_phpconf ${PHPHAND}" 
        echo -e "\n${HEADER/TEXT/PHP MODULES}\n"
	php -m | tr '\n' ' ' | sed 's/\(\[Z.*s\]\)/\n\n\1/'
}
 
mysqlopts () {
	echo -e "\n${HEADER/TEXT/MYSQL}\n"
	echo -e "${CATEGORY/TEXT/MySQL Version} ${MYSQLV}"
        echo -e "${CATEGORY/TEXT/MySQL Current Status}\n${MYSQLSTAT}"
	echo -e "${CATEGORY/TEXT/MySQL Datadir} ${MYSQLDATA}"
	echo -e "${CATEGORY/TEXT/Databases}" ${DBS}
}

appopts () {
        echo -e "\n\n${HEADER/TEXT/EXTRA SOFTWARE}\n"
	[[ $(which convert 2> /dev/null) ]] && echo -e "ImageMagick => ${INSTALLED}"|| echo -e "ImageMagick => ${NOTFOUND}"
	[[ $(which ffmpeg 2> /dev/null) ]] && echo -e "FFMPEG => ${INSTALLED}" || echo -e "FFMPEG => ${NOTFOUND}"
	[[ $(which nginx 2> /dev/null) ]] && echo -e "Nginx => ${INSTALLED}" || echo -e "Nginx: ${NOTFOUND}"
	[[ $(which svn 2> /dev/null) ]] && echo -e "SVN => ${INSTALLED}" || echo -e "SVN: ${NOTFOUND}"
	[[ $(which postgres 2> /dev/null) ]] && echo -e "Postgresql => ${INSTALLED}" || echo -e "Postgresql => ${NOTFOUND}"
	[[ $(pgrep xcache 2> /dev/null) ]] && echo -e "XCache => ${INSTALLED}" || echo -e "XCache => ${NOTFOUND}"
        [[ $(pgrep eaccelerator 2> /dev/null) ]] && echo -e "eaccelerator => ${INSTALLED}" || echo -e "eaccelerator => ${NOTFOUND}"
        [[ $(pgrep memcache 2> /dev/null) ]] && echo -e "memcache => ${INSTALLED}" || echo -e "memcache => ${NOTFOUND}"
        [[ $(pgrep nginx 2> /dev/null) ]] && echo -e "nginx => ${INSTALLED}" || echo -e "nginx => ${NOTFOUND}"
        [[ $(pgrep postgres 2> /dev/null) ]] && echo -e "postgres => ${INSTALLED}" || echo -e "postgres => ${NOTFOUND}"
	[[ $(php -i | grep apc.cache 2> /dev/null) ]] && echo -e "APC => ${INSTALLED}" || echo -e "APC => ${NOTFOUND}"
}

writeinfo () {
serverinfo
phpopts
mysqlopts
appopts
}
 
userips () {
touch ${DIR}/dedips.txt
touch ${DIR}/sharedips.txt
for cpuser in ${ALLUSERS};
do
	if [[ $MAINIP = $(grep IP $CPUSERSPATH/$cpuser | cut -d'=' -f2) ]]
		then 
			echo $cpuser >> ${DIR}/sharedips.txt
		else
			echo "$cpuser: $(grep IP $CPUSERSPATH/$cpuser | cut -d'=' -f2)" >> ${DIR}/dedips.txt
	fi
done
}
 
spacetest () {
#backup files to backup drive, query if this is ok
echo "Current disk usage:"
df -h
echo "
Calculating Space needed...
"
echo $(du -csh ${FILES} 2>/dev/null |grep total) estimated space needed.
echo -n "Copy server config files to ${DIR}? "
query
}

backupcfgs () {
mkdir -p ${DIR}
echo "Saving server config data to ${DIR}/serverinfo.txt!"  
serverinfo >> ${DIR}/serverinfo.txt
phpopts >> ${DIR}/serverinfo.txt
mysqlopts >> ${DIR}/serverinfo.txt
appopts >> ${DIR}/serverinfo.txt
php -i > ${DIR}/php-i.txt
sleep 1
echo "Dumping mysql grants to ${DIR}/mysqlgrants.txt!"
mysql -B -N -e "SELECT DISTINCT CONCAT('SHOW GRANTS FOR ''', user, '''@''', host, ''';') AS query FROM mysql.user" | egrep -v '(root|horde|cphulkd|eximstats|modsec|roundcube|liquidweb.com)' | mysql $@ | sed 's/\(GRANT .*\)/\1;/;s/^\(Grants for .*\)/## \1 ##/;/##/{x;p;x;}' > ${DIR}/mysqlgrants.txt
sleep 1
#printopts
echo "Saving cpanel users to ${DIR}/users.txt!"
echo ${ALLUSERS} > $DIR/users.txt
sleep 1
echo "Saving user Ips to ${DIR}/sharedips.txt and ${DIR}/dedips.txt!"
userips
sleep 1
echo "Copying miscellaneous cpanel files to ${DIR}, this may take some time..."
for file in ${FILES} ; do echo -n "Copying ${file}... "; rsync -aqHR ${file} ${DIR}/ 2> ${DIR}/rsync.log; done
echo 'Config backup complete!'
}

lowerttls () {
echo "Lowering TTL's!"
sleep 1
sed -i.lwbak -e 's/^\$TTL.*/$TTL 300/g' -e 's/[0-9]\{10\}/'`date +%Y%m%d%H`'/g' /var/named/*.db
rndc reload
}

backupscript () {
#Test for pkgacct
if [ -s /usr/local/cpanel/scripts/pkgacct ]
	then
		#Test for previous backups
		if [[ -d ${BACKDIR} ]]
			then
				if yesorno "${BACKDIR} found! Do you want to move it? (Saying 'no' will overwrite the backups in that directory)"
				then
					mv ${BACKDIR} ${BACKDIR}.$(date +%Y%m%d%H)
					mkdir -p ${BACKDIR}
					for user in ${ALLUSERS}; do echo -e "\nBacking up ${user}"; /usr/local/cpanel/scripts/pkgacct --skiphomedir ${user} ${BACKDIR} cpmove nocompress 1>> ${BACKDIR}/backup.log; echo -e "\t${user} is backuped.\n"; done
				else
					for user in ${ALLUSERS}; do echo -e "\nBacking up ${user}"; /usr/local/cpanel/scripts/pkgacct --skiphomedir ${user} ${BACKDIR} cpmove nocompress 1>> ${BACKDIR}/backup.log; echo -e "\t${user} is backuped.\n"; done
				fi
			else
				mkdir -p ${BACKDIR}
				for user in ${ALLUSERS}; do echo -e "\nBacking up ${user}"; /usr/local/cpanel/scripts/pkgacct --skiphomedir ${user} ${BACKDIR} cpmove nocompress 1>> ${BACKDIR}/backup.log; echo -e "\t${user} is backuped.\n"; done
		fi	
	else
		echo "/usr/local/cpanel/scripts not found! Exiting."
		exit 1
fi
}

#Option to backup accounts after scriptruns
makebackups () {
if yesorno "Do you want to lower TTLs? " 
	then
		lowerttls
fi
echo -n "Do you want to write --skiphomedir backups to ${DIR}/backups? "
query
backupscript
}

mvcpbackup () {
echo -n "Move /backup/cpbackup to /backup/cpbackup.pre-root? "
query
#check for existing pre-root directory!
if [ -d /backup/cpbackup.pre-root ]
then
	echo "Moving previous pre-root backup!"
	sleep 1	
	mv /backup/cpbackup.pre-root{,.$(date +%F.%T)}
fi
if [ -d /backup/cpbackup ]; then
	echo "Moving backups to pre-root!"
	sleep 1
	mv /backup/cpbackup{,.pre-root}
else
	echo "No backup dir found. Not moving a darn thing."
	sleep 1
fi
}

##Output starts here
clear 
echo "
Getopts ${VERSION}!
Report issues to abrevick@liquidweb.com

Lets back this thang up!

Currently accepted arguments:
justconfigs
backup
--force 
"
 
main () {
settinthevars
#start here
if [ -d ${DIR} ]
then
	echo "${DIR} exists. Enter 'y' to move it, or 'n' to exit."
	query
	mv $DIR{,.$(date +%F-%T)}
	spacetest
	backupcfgs
	makebackups
	mvcpbackup
else
	spacetest
	backupcfgs
	makebackups
	mvcpbackup
fi
}
 
#Check for arguments, otherwise run the main loop 
# $1 variable not recognised inside the functions
case $1 in
justconfigs)
	#conifgs only
	force=yes
	settinthevars
	spacetest
	backupcfgs
	echo "Just configs done!"
;;
backup)
	#only make backups
	settinthevars
	makebackups
	echo "Just backups done!"
;;
--force)
	#don't ask y/n questions
	force=yes
	main
	echo "I hope you notice I didn't ask you any questions."
;;
*)
	main
	echo "Server is backuped."
;;
esac
