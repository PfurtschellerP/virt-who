FROM rockylinux/rockylinux:10-minimal

# install updates and packages
RUN microdnf update -y
RUN microdnf install subscription-manager virt-who-1.32.1 -y
RUN microdnf clean all

# copy files
COPY entrypoint.sh /entrypoint.sh
COPY render_config.py /usr/local/bin/render-virt-who-config

# set permissions
RUN chmod 0755 /entrypoint.sh /usr/local/bin/render-virt-who-config

# entrypoint
ENTRYPOINT ["/entrypoint.sh"]