# In order to run this with systemd you must do one of the following
# use  --privileged  when running the container
# mount the volume when running the container -v /sys/fs/cgroup:/sys/fs/cgroup:ro
# docker run –privileged -ti -v /sys/fs/cgroup:/sys/fs/cgroup:ro -p 2222:22 
FROM centos:7
EXPOSE 22
ENV LC_ALL="en_US.UTF-8" LANG="en_US.UTF-8" LANGUAGE="en_US.UTF-8"
RUN echo "LANG=en_US.UTF-8" > /etc/locale.conf
STOPSIGNAL SIGRTMIN+3
ADD live_audit.sh /usr/bin/live_audit.sh
RUN yum -y install epel-release systemd rsync tree vim openssh openssh-server openssh-clients anacron sudo curl openssl; yum clean all;
RUN yum -y inotify-tools && mkdir /root/bolt_scripts
RUN (cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i == systemd-tmpfiles-setup.service ] || rm -f $i; done); \ 
  rm -f /lib/systemd/system/multi-user.target.wants/*; \
  rm -f /etc/systemd/system/*.wants/*; \
  rm -f /lib/systemd/system/local-fs.target.wants/*; \
  rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
  rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
  rm -f /lib/systemd/system/basic.target.wants/*; \
  rm -f /lib/systemd/system/anaconda.target.wants/*; \
  rm -rf /var/cache/yum; \
  echo "root:test" | chpasswd; \
  useradd -m -s /bin/bash centos && echo "centos:test" | chpasswd; \
  ln -s '/usr/lib/systemd/system/sshd.service' '/etc/systemd/system/multi-user.target.wants/sshd.service'
VOLUME [ “/sys/fs/cgroup” ]
CMD /sbin/init
# ENTRYPOINT [ "/sbin/init" ]
