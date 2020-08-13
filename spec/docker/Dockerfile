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
ADD live_audit.service /etc/systemd/system/live_audit.service
RUN chmod 644 /etc/systemd/system/live_audit.service && chmod 755 /usr/bin/live_audit.sh && \
    echo "root:test" | chpasswd; \
    useradd -m -s /bin/bash centos && echo "centos:test" | chpasswd; 
RUN yum -y install epel-release systemd rsync tree vim openssh openssh-server openssh-clients anacron sudo curl openssl
RUN yum -y install inotify-tools && mkdir /root/bolt_scripts && yum clean all
# remove any scripts that don't need to be run
RUN (cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i == systemd-tmpfiles-setup.service ] || rm -f $i; done); \ 
  rm -f /lib/systemd/system/multi-user.target.wants/*; \
  rm -f /etc/systemd/system/*.wants/*; \
  rm -f /lib/systemd/system/local-fs.target.wants/*; \
  rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
  rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
  rm -f /lib/systemd/system/basic.target.wants/*; \
  rm -f /lib/systemd/system/anaconda.target.wants/*; \
  rm -rf /var/cache/yum; \
  ln -s '/usr/lib/systemd/system/sshd.service' '/etc/systemd/system/multi-user.target.wants/sshd.service' && \
  ln -s '/etc/systemd/system/live_audit.service' '/etc/systemd/system/multi-user.target.wants/live_audit.service'
ARG HOST="localhost"
RUN mkdir -p /root/.puppetlabs/client-tools && \
    echo $' \n\
{ \n\
  "puppetdb": { \n\
    "server_urls": "https://'$HOST$':8081", \n\
    "cacert": "/etc/puppetlabs/puppet/ssl/certs/ca.pem", \n\
    "cert": "/etc/puppetlabs/puppet/ssl/certs/'$HOST$'.pem", \n\
    "key": "/etc/puppetlabs/puppet/ssl/private_keys/'$HOST$'.pem" \n\
  } \n\
} \n '\
> /root/.puppetlabs/client-tools/puppetdb.conf
VOLUME ["/sys/fs/cgroup"]
#CMD /bin/bash
ENTRYPOINT /sbin/init
